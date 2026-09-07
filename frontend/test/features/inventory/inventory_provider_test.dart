import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockInventoryRepository extends Mock implements InventoryRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Product _makeProduct({
  String id = 'p1',
  String name = 'Producto Test',
  int availableStock = 20,
  int? minStockAlert = 5,
  String category = 'Bebidas',
}) {
  return Product(
    id: id,
    sku: 'NEX-T0001',
    name: name,
    category: category,
    priceMxn: 10.0,
    costMxn: 6.0,
    stock: availableStock,
    reservedStock: 0,
    availableStock: availableStock,
    minStockAlert: minStockAlert,
    isActive: true,
    isOnCatalog: true,
    createdAt: DateTime(2026, 9, 1),
  );
}

PaginatedProducts _makePage({
  List<Product>? items,
  int total = 1,
  int page = 1,
  int totalPages = 1,
}) {
  return PaginatedProducts(
    items: items ?? [_makeProduct()],
    total: total,
    page: page,
    pageSize: 20,
    totalPages: totalPages,
  );
}

/// Crea un [ProviderContainer] con el mock inyectado y espera a que
/// la carga inicial (microtask del build) termine.
Future<ProviderContainer> _makeContainer(
  MockInventoryRepository mock,
) async {
  final container = ProviderContainer(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(mock),
    ],
  );
  // Inicializa el provider
  container.read(inventoryProvider);
  // Espera el microtask de carga inicial
  await Future<void>.delayed(Duration.zero);
  return container;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockInventoryRepository mock;

  setUp(() {
    mock = MockInventoryRepository();
  });

  // Fallback para cualquier llamada a getProducts con parámetros nombrados
  setUpAll(() {
    registerFallbackValue(
      _makePage(),
    );
  });

  // ── Helper que configura la respuesta por defecto del mock ──────────────
  void stubGetProducts({
    List<Product>? items,
    int total = 1,
    int totalPages = 1,
    int page = 1,
    bool throws = false,
  }) {
    when(
      () => mock.getProducts(
        query: any(named: 'query'),
        category: any(named: 'category'),
        lowStock: any(named: 'lowStock'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async {
      if (throws) throw Exception('Sin conexión');
      return _makePage(
        items: items,
        total: total,
        page: page,
        totalPages: totalPages,
      );
    });
  }

  // ── 1. Estado inicial ────────────────────────────────────────────────────
  group('estado inicial', () {
    test('query vacío, sin filtros, isLoading true antes de la primera carga',
        () {
      stubGetProducts();
      final container = ProviderContainer(
        overrides: [inventoryRepositoryProvider.overrideWithValue(mock)],
      );
      addTearDown(container.dispose);

      final state = container.read(inventoryProvider);

      expect(state.query, isEmpty);
      expect(state.activeCategory, isNull);
      expect(state.showLowStock, isFalse);
      expect(state.isLoading, isTrue);
      expect(state.products, isEmpty);
    });
  });

  // ── 2. Carga inicial exitosa ─────────────────────────────────────────────
  group('loadProducts — primera carga', () {
    test('puebla products y desactiva isLoading', () async {
      final products = [_makeProduct(id: 'p1'), _makeProduct(id: 'p2')];
      stubGetProducts(items: products, total: 2);

      final container = await _makeContainer(mock);
      addTearDown(container.dispose);

      final state = container.read(inventoryProvider);

      expect(state.isLoading, isFalse);
      expect(state.products.length, 2);
      expect(state.currentPage, 1);
      expect(state.error, isNull);
    });
  });

  // ── 3. Búsqueda ──────────────────────────────────────────────────────────
  group('setQuery', () {
    test('actualiza query y resetea página a 1', () async {
      stubGetProducts();
      final container = await _makeContainer(mock);
      addTearDown(container.dispose);

      container.read(inventoryProvider.notifier).setQuery('coca');
      // No esperamos el debounce — solo verificamos el estado inmediato
      final state = container.read(inventoryProvider);

      expect(state.query, 'coca');
      expect(state.currentPage, 1);
    });

    test('debounce dispara la carga tras 300 ms', () async {
      stubGetProducts();
      final container = await _makeContainer(mock);
      addTearDown(container.dispose);

      container.read(inventoryProvider.notifier).setQuery('leche');
      await Future<void>.delayed(const Duration(milliseconds: 350));

      verify(
        () => mock.getProducts(
          query: 'leche',
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        ),
      ).called(1);
    });
  });

  // ── 4. Filtro categoría ───────────────────────────────────────────────────
  group('setCategory', () {
    test('activa categoría y resetea página', () async {
      stubGetProducts();
      final container = await _makeContainer(mock);
      addTearDown(container.dispose);

      container.read(inventoryProvider.notifier).setCategory('Bebidas');
      await Future<void>.delayed(Duration.zero);

      final state = container.read(inventoryProvider);
      expect(state.activeCategory, 'Bebidas');
      expect(state.currentPage, 1);
    });

    test('setCategory(null) limpia el filtro', () async {
      stubGetProducts();
      final container = await _makeContainer(mock);
      addTearDown(container.dispose);

      container.read(inventoryProvider.notifier).setCategory('Bebidas');
      await Future<void>.delayed(Duration.zero);
      container.read(inventoryProvider.notifier).setCategory(null);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(inventoryProvider).activeCategory, isNull);
    });
  });

  // ── 5. Filtro stock bajo ──────────────────────────────────────────────────
  group('toggleLowStock', () {
    test('primera llamada activa showLowStock', () async {
      stubGetProducts();
      final container = await _makeContainer(mock);
      addTearDown(container.dispose);

      container.read(inventoryProvider.notifier).toggleLowStock();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(inventoryProvider).showLowStock, isTrue);
    });

    test('segunda llamada desactiva showLowStock', () async {
      stubGetProducts();
      final container = await _makeContainer(mock);
      addTearDown(container.dispose);

      container.read(inventoryProvider.notifier).toggleLowStock();
      await Future<void>.delayed(Duration.zero);
      container.read(inventoryProvider.notifier).toggleLowStock();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(inventoryProvider).showLowStock, isFalse);
    });
  });

  // ── 6. Paginación ─────────────────────────────────────────────────────────
  group('loadMore', () {
    test('incrementa currentPage y acumula productos', () async {
      // Página 1
      when(
        () => mock.getProducts(
          query: any(named: 'query'),
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: 1,
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((_) async => _makePage(
            items: [_makeProduct(id: 'p1')],
            total: 2,
            page: 1,
            totalPages: 2,
          ));

      // Página 2
      when(
        () => mock.getProducts(
          query: any(named: 'query'),
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: 2,
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((_) async => _makePage(
            items: [_makeProduct(id: 'p2')],
            total: 2,
            page: 2,
            totalPages: 2,
          ));

      final container = await _makeContainer(mock);
      addTearDown(container.dispose);

      await container.read(inventoryProvider.notifier).loadMore();

      final state = container.read(inventoryProvider);
      expect(state.currentPage, 2);
      expect(state.products.length, 2);
      expect(state.products.map((p) => p.id), containsAll(['p1', 'p2']));
    });

    test('no dispara si ya está en la última página', () async {
      stubGetProducts(total: 1, totalPages: 1);
      final container = await _makeContainer(mock);
      addTearDown(container.dispose);

      final pagesBefore = container.read(inventoryProvider).currentPage;
      await container.read(inventoryProvider.notifier).loadMore();

      expect(container.read(inventoryProvider).currentPage, pagesBefore);
    });
  });

  // ── 7. Error y retry ─────────────────────────────────────────────────────
  group('error y retry', () {
    test('error del repositorio setea campo error y apaga isLoading', () async {
      stubGetProducts(throws: true);
      final container = await _makeContainer(mock);
      addTearDown(container.dispose);

      final state = container.read(inventoryProvider);
      expect(state.error, isNotNull);
      expect(state.isLoading, isFalse);
    });

    test('retry limpia error y recarga', () async {
      // Primera llamada lanza error
      var callCount = 0;
      when(
        () => mock.getProducts(
          query: any(named: 'query'),
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) throw Exception('Sin conexión');
        return _makePage();
      });

      final container = await _makeContainer(mock);
      addTearDown(container.dispose);

      // Confirma error tras primera carga
      expect(container.read(inventoryProvider).error, isNotNull);

      // Retry
      await container.read(inventoryProvider.notifier).retry();

      final state = container.read(inventoryProvider);
      expect(state.error, isNull);
      expect(state.products, isNotEmpty);
    });
  });
}
