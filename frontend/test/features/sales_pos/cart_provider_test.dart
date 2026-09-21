import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/features/account/data/operating_warehouse_store.dart';
import 'package:nexus_app/features/account/presentation/account_provider.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart'
    show WarehouseOption, inventoryProvider, warehousesProvider;
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_state.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';
import 'package:nexus_app/features/sales_pos/presentation/cart_provider.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockSalesRepository extends Mock implements SalesRepository {}
class MockInventoryRepository extends Mock implements InventoryRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Product _makeProduct({
  String id = 'prod-001',
  String name = 'Coca-Cola 600ml',
  double price = 18.0,
}) {
  return Product(
    id: id,
    sku: 'NEX-B0001',
    name: name,
    category: 'Bebidas',
    priceMxn: price,
    costMxn: 11.0,
    stock: 48,
    reservedStock: 0,
    availableStock: 48,
    isActive: true,
    isOnCatalog: false,
    createdAt: DateTime(2026, 9, 1),
  );
}

// ---------------------------------------------------------------------------
// Helper — monta un ProviderContainer con el repo mockeado
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({MockSalesRepository? repo}) {
  final mock = repo ?? MockSalesRepository();
  return ProviderContainer(
    overrides: [
      salesRepositoryProvider.overrideWithValue(mock),
    ],
  );
}

/// Container con la cadena completa de overrides que `checkout()` necesita
/// para resolver `operatingWarehouseProvider` (almacén operativo real) —
/// mismo combo usado en `checkout_screen_test.dart`.
ProviderContainer _makeCheckoutContainer({
  required MockSalesRepository salesRepo,
  required MockInventoryRepository inventoryRepo,
}) {
  return ProviderContainer(
    overrides: [
      salesRepositoryProvider.overrideWithValue(salesRepo),
      inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
      operatingWarehouseStoreProvider
          .overrideWithValue(OperatingWarehouseStoreMemory()),
      authRepositoryProvider
          .overrideWithValue(AuthRepositoryMock(storage: SecureStorage())),
      warehousesProvider.overrideWith((ref) async => const [
            WarehouseOption(
                id: 'wh-001', name: 'Almacén Principal', isDefault: true),
          ]),
    ],
  );
}

void _stubInventoryRepoGetProducts(MockInventoryRepository repo) {
  when(() => repo.getProducts(
        query: any(named: 'query'),
        category: any(named: 'category'),
        lowStock: any(named: 'lowStock'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      )).thenAnswer((_) async => const PaginatedProducts(
        items: [],
        total: 0,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      ));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(<CartItem>[]);
    registerFallbackValue('CASH_MXN');
  });

  // ── Estado inicial vacío ─────────────────────────────────────────────────
  test('estado inicial: carrito vacío y totales en cero', () {
    final container = _makeContainer();
    addTearDown(container.dispose);

    final state = container.read(cartProvider);

    expect(state.items, isEmpty);
    expect(state.totalMxn, 0.0);
    expect(state.itemCount, 0);
    expect(state.isEmpty, isTrue);
  });

  // ── addProduct — producto nuevo ──────────────────────────────────────────
  test('addProduct añade un nuevo producto al carrito', () {
    final container = _makeContainer();
    addTearDown(container.dispose);

    final product = _makeProduct();
    container.read(cartProvider.notifier).addProduct(product);

    final state = container.read(cartProvider);
    expect(state.items.length, 1);
    expect(state.items.first.productId, product.id);
    expect(state.items.first.quantity, 1);
  });

  // ── addProduct — acumula si ya existe ────────────────────────────────────
  test('addProduct incrementa cantidad si el producto ya está en el carrito',
      () {
    final container = _makeContainer();
    addTearDown(container.dispose);

    final product = _makeProduct();
    container.read(cartProvider.notifier).addProduct(product);
    container.read(cartProvider.notifier).addProduct(product);

    final state = container.read(cartProvider);
    expect(state.items.length, 1);
    expect(state.items.first.quantity, 2);
  });

  // ── addOnTheFly ──────────────────────────────────────────────────────────
  test('addOnTheFly añade ítem sin productId y con isOnTheFly = true', () {
    final container = _makeContainer();
    addTearDown(container.dispose);

    container.read(cartProvider.notifier).addOnTheFly(
          name: 'Frituras caseras',
          priceMxn: 25.0,
          qty: 2,
        );

    final state = container.read(cartProvider);
    expect(state.items.length, 1);
    expect(state.items.first.productId, isNull);
    expect(state.items.first.isOnTheFly, isTrue);
    expect(state.items.first.quantity, 2);
    expect(state.items.first.name, 'Frituras caseras');
  });

  // ── updateQty a 0 elimina el ítem ────────────────────────────────────────
  test('updateQty con qty = 0 elimina el ítem del carrito', () {
    final container = _makeContainer();
    addTearDown(container.dispose);

    final product = _makeProduct();
    container.read(cartProvider.notifier).addProduct(product);
    final itemId = container.read(cartProvider).items.first.id;

    container.read(cartProvider.notifier).updateQty(itemId, 0);

    expect(container.read(cartProvider).items, isEmpty);
  });

  // ── removeItem ───────────────────────────────────────────────────────────
  test('removeItem elimina solo el ítem indicado', () {
    final container = _makeContainer();
    addTearDown(container.dispose);

    container
        .read(cartProvider.notifier)
        .addProduct(_makeProduct(id: 'prod-001', name: 'Coca-Cola'));
    container
        .read(cartProvider.notifier)
        .addProduct(_makeProduct(id: 'prod-002', name: 'Sabritas'));

    final itemToRemove = container.read(cartProvider).items.first.id;
    container.read(cartProvider.notifier).removeItem(itemToRemove);

    final state = container.read(cartProvider);
    expect(state.items.length, 1);
    expect(state.items.first.name, 'Sabritas');
  });

  // ── clear ────────────────────────────────────────────────────────────────
  test('clear vacía el carrito completamente', () {
    final container = _makeContainer();
    addTearDown(container.dispose);

    container
        .read(cartProvider.notifier)
        .addProduct(_makeProduct(id: 'prod-001'));
    container
        .read(cartProvider.notifier)
        .addProduct(_makeProduct(id: 'prod-002', name: 'Sabritas'));

    container.read(cartProvider.notifier).clear();

    final state = container.read(cartProvider);
    expect(state.items, isEmpty);
    expect(state.totalMxn, 0.0);
  });

  // ── totalMxn ─────────────────────────────────────────────────────────────
  test('totalMxn calcula correctamente la suma de subtotales', () {
    final container = _makeContainer();
    addTearDown(container.dispose);

    // Coca-Cola $18 × 2 = $36
    container
        .read(cartProvider.notifier)
        .addProduct(_makeProduct(id: 'prod-001', price: 18.0));
    container
        .read(cartProvider.notifier)
        .addProduct(_makeProduct(id: 'prod-001', price: 18.0)); // qty → 2
    // Sabritas $16.50 × 1 = $16.50
    container.read(cartProvider.notifier).addProduct(
        _makeProduct(id: 'prod-002', name: 'Sabritas', price: 16.50));

    final total = container.read(cartProvider).totalMxn;
    expect(total, closeTo(52.50, 0.01));
  });

  // ── itemCount ────────────────────────────────────────────────────────────
  test('itemCount devuelve el total de unidades del carrito', () {
    final container = _makeContainer();
    addTearDown(container.dispose);

    // 2 × Coca-Cola + 3 × Sabritas = 5 unidades
    container
        .read(cartProvider.notifier)
        .addProduct(_makeProduct(id: 'prod-001'), qty: 2);
    container
        .read(cartProvider.notifier)
        .addProduct(_makeProduct(id: 'prod-002', name: 'Sabritas'), qty: 3);

    expect(container.read(cartProvider).itemCount, 5);
  });

  // ── Regresión: checkout exitoso invalida inventoryProvider ───────────────
  // Bug real reportado en QA de dispositivo (Sep 2026): "al vender no se
  // descuenta el stock" — el backend sí descontaba, pero `inventoryProvider`
  // nunca se refrescaba tras un checkout, así que Inventario/Detalle de
  // producto seguían mostrando el stock cacheado de antes de la venta.
  test('checkout exitoso invalida inventoryProvider para refrescar el stock',
      () async {
    final salesRepo = MockSalesRepository();
    final inventoryRepo = MockInventoryRepository();
    _stubInventoryRepoGetProducts(inventoryRepo);
    when(() => salesRepo.checkout(
          items: any(named: 'items'),
          payments: any(named: 'payments'),
          cashierName: any(named: 'cashierName'),
          warehouseId: any(named: 'warehouseId'),
        )).thenAnswer((_) async => CheckoutResult(
          saleId: 'sale-001',
          folio: 'NV-2026-000001',
          totalMxn: 18.0,
          totalPaidMxn: 18.0,
          changeGivenMxn: 0.0,
          items: const [],
          payments: const [],
          cashierName: 'Cajero de prueba',
          completedAt: DateTime(2026, 9, 18, 12, 0),
        ));

    final container = _makeCheckoutContainer(
      salesRepo: salesRepo,
      inventoryRepo: inventoryRepo,
    );
    addTearDown(container.dispose);

    container.read(cartProvider.notifier).addProduct(_makeProduct());

    // Lee `inventoryProvider` para que exista y quede "watched" — refleja
    // el caso real (Inventario/Checkout comparten el mismo provider vivo).
    container.read(inventoryProvider);
    while (container.read(inventoryProvider).isLoading) {
      await Future<void>.delayed(Duration.zero);
    }
    verify(() => inventoryRepo.getProducts(
          query: any(named: 'query'),
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).called(1);

    await container.read(cartProvider.notifier).checkout(
      payments: const [
        PaymentEntry(
          id: 'pay-1',
          method: PaymentMethodMxn.cashMxn,
          amountMxn: 18.0,
        ),
      ],
    );

    // El checkout invalidó inventoryProvider — leerlo de nuevo dispara una
    // segunda llamada real a `getProducts` en vez de servir el caché viejo.
    container.read(inventoryProvider);
    while (container.read(inventoryProvider).isLoading) {
      await Future<void>.delayed(Duration.zero);
    }
    verify(() => inventoryRepo.getProducts(
          query: any(named: 'query'),
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).called(1);
  });
}
