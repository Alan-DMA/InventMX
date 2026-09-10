import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/router/app_router.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/product_list_tile.dart';
import 'package:nexus_app/features/onboarding/presentation/onboarding_provider.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockInventoryRepository extends Mock implements InventoryRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Product _makeProduct({
  String id = 'p1',
  String name = 'Coca-Cola 600ml',
  int availableStock = 20,
  int? minStockAlert = 5,
  double priceMxn = 18.0,
}) {
  return Product(
    id: id,
    sku: 'NEX-B0001',
    name: name,
    category: 'Bebidas',
    priceMxn: priceMxn,
    costMxn: 11.0,
    stock: availableStock,
    reservedStock: 0,
    availableStock: availableStock,
    minStockAlert: minStockAlert,
    isActive: true,
    isOnCatalog: true,
    createdAt: DateTime(2026, 9, 1),
  );
}

PaginatedProducts _makeEmptyPage() => const PaginatedProducts(
      items: [],
      total: 0,
      page: 1,
      pageSize: 20,
      totalPages: 1,
    );

PaginatedProducts _makePage(List<Product> items) => PaginatedProducts(
      items: items,
      total: items.length,
      page: 1,
      pageSize: 20,
      totalPages: 1,
    );

/// Construye la app completa con GoRouter autenticado y onboarding completo,
/// apuntando a la ruta /dashboard/inventory.
Widget _buildApp(MockInventoryRepository mock) {
  return ProviderScope(
    overrides: [
      sessionProvider.overrideWith((ref) => true),
      onboardingCompleteProvider.overrideWith((ref) => true),
      inventoryRepositoryProvider.overrideWithValue(mock),
    ],
    child: Consumer(
      builder: (_, ref, __) => MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: ref.watch(appRouterProvider),
      ),
    ),
  );
}

void _stubProducts(MockInventoryRepository mock, List<Product> items) {
  when(
    () => mock.getProducts(
      query: any(named: 'query'),
      category: any(named: 'category'),
      lowStock: any(named: 'lowStock'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    ),
  ).thenAnswer((_) async => _makePage(items));
}

void _stubEmpty(MockInventoryRepository mock) {
  when(
    () => mock.getProducts(
      query: any(named: 'query'),
      category: any(named: 'category'),
      lowStock: any(named: 'lowStock'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    ),
  ).thenAnswer((_) async => _makeEmptyPage());
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockInventoryRepository mock;

  setUp(() => mock = MockInventoryRepository());

  // ── CA-01: Tiles con nombre y precio MXN ─────────────────────────────────
  testWidgets('CA-01: muestra tiles con nombre y precio MXN', (tester) async {
    _stubProducts(mock, [
      _makeProduct(id: 'p1', name: 'Coca-Cola 600ml', priceMxn: 18.0),
      _makeProduct(id: 'p2', name: 'Pepsi 2L', priceMxn: 32.0),
    ]);

    await tester.pumpWidget(_buildApp(mock));
    await tester.pumpAndSettle();

    expect(find.text('Coca-Cola 600ml'), findsOneWidget);
    expect(find.text('Pepsi 2L'), findsOneWidget);
    // Precio en formato $ MXN
    expect(find.text('\$18.00'), findsOneWidget);
    expect(find.text('\$32.00'), findsOneWidget);
  });

  // ── CA-01: Badge rojo en stock cero ───────────────────────────────────────
  testWidgets('CA-01: badge "Sin stock" cuando availableStock == 0',
      (tester) async {
    _stubProducts(mock, [
      _makeProduct(id: 'p1', name: 'Agua Ciel', availableStock: 0),
    ]);

    await tester.pumpWidget(_buildApp(mock));
    await tester.pumpAndSettle();

    expect(find.text('Sin stock'), findsOneWidget);
  });

  // ── CA-01: Badge ámbar en stock bajo ──────────────────────────────────────
  testWidgets('CA-01: badge con cantidad cuando stock <= minStockAlert',
      (tester) async {
    _stubProducts(mock, [
      _makeProduct(
        id: 'p1',
        name: 'Leche Lala',
        availableStock: 3,
        minStockAlert: 5,
      ),
    ]);

    await tester.pumpWidget(_buildApp(mock));
    await tester.pumpAndSettle();

    // Stock bajo muestra la cantidad (no "Sin stock")
    expect(find.text('3 pzs'), findsOneWidget);
    // Verifica que el tile existe
    expect(find.byType(ProductListTile), findsOneWidget);
  });

  // ── CA-06: Empty state sin productos ─────────────────────────────────────
  testWidgets('CA-06: empty state con CTA cuando no hay productos',
      (tester) async {
    _stubEmpty(mock);

    await tester.pumpWidget(_buildApp(mock));
    await tester.pumpAndSettle();

    expect(find.text('Aún no tienes productos'), findsOneWidget);
    expect(find.text('Agregar tu primer producto'), findsOneWidget);
  });

  // ── CA-08: NavigationBar con 4 tabs ──────────────────────────────────────
  testWidgets('CA-08: NavigationBar tiene 4 tabs', (tester) async {
    _stubProducts(mock, [_makeProduct()]);

    await tester.pumpWidget(_buildApp(mock));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    // "Inventario" aparece en AppBar title y en NavigationDestination label
    expect(find.text('Inventario'), findsWidgets);
    expect(find.text('Ventas'), findsOneWidget);
    expect(find.text('Caja'), findsOneWidget);
    expect(find.text('Reportes'), findsOneWidget);
  });

  // ── CA-08: Tap en tab Ventas navega al CheckoutScreen ────────────────────
  testWidgets('CA-08: tap en tab Ventas muestra la pantalla de ventas',
      (tester) async {
    _stubProducts(mock, [_makeProduct()]);

    await tester.pumpWidget(_buildApp(mock));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ventas'));
    await tester.pumpAndSettle();

    // CheckoutScreen muestra el empty state del carrito
    expect(find.text('Carrito vacío'), findsOneWidget);
    expect(find.text('Ventas'), findsWidgets);
  });
}
