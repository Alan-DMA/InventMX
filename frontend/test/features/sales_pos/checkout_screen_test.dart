import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_state.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';
import 'package:nexus_app/features/sales_pos/presentation/cart_provider.dart';
import 'package:nexus_app/features/sales_pos/presentation/checkout_screen.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockInventoryRepository extends Mock implements InventoryRepository {}
class MockSalesRepository extends Mock implements SalesRepository {}

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
    costMxn: 0,
    stock: 48,
    reservedStock: 0,
    availableStock: 48,
    isActive: true,
    isOnCatalog: false,
    createdAt: DateTime(2026, 9, 1),
  );
}

void _stubInventoryRepo(MockInventoryRepository repo,
    {List<Product>? products}) {
  when(() => repo.getProducts(
        query: any(named: 'query'),
        category: any(named: 'category'),
        lowStock: any(named: 'lowStock'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      )).thenAnswer((_) async => PaginatedProducts(
        items: products ?? [],
        total: products?.length ?? 0,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      ));
}

void _stubSalesRepo(MockSalesRepository repo) {
  when(() => repo.checkout(
        items: any(named: 'items'),
        payments: any(named: 'payments'),
        cashierName: any(named: 'cashierName'),
      )).thenAnswer((_) async => CheckoutResult(
        saleId: 'sale-001',
        folio: 'NV-2026-001548',
        totalMxn: 18.0,
        totalPaidMxn: 18.0,
        changeGivenMxn: 0.0,
        items: const [],
        payments: const [],
        cashierName: 'Cajero de prueba',
        completedAt: DateTime(2026, 9, 10, 12, 0),
      ));
}

// ---------------------------------------------------------------------------
// Helper de montaje
// ---------------------------------------------------------------------------

Widget _buildScreen({
  MockInventoryRepository? inventoryRepo,
  MockSalesRepository? salesRepo,
  List<CartItem> initialCartItems = const [],
}) {
  final inv = inventoryRepo ?? MockInventoryRepository();
  final sal = salesRepo ?? MockSalesRepository();
  _stubInventoryRepo(inv);
  _stubSalesRepo(sal);

  return ProviderScope(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(inv),
      salesRepositoryProvider.overrideWithValue(sal),
      // Pre-carga ítems en el carrito si se especifican
      if (initialCartItems.isNotEmpty)
        cartProvider.overrideWith(() {
          final notifier = CartNotifier();
          return notifier;
        }),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const CheckoutScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(<CartItem>[]);
    registerFallbackValue(<PaymentEntry>[]);
  });

  // ── CA-01: empty state visible con carrito vacío ─────────────────────────
  testWidgets('muestra empty state con carrito vacío', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pump();

    expect(find.text('Carrito vacío'), findsOneWidget);
    expect(find.text('Ventas'), findsOneWidget);
  });

  // ── CA-04: botón Cobrar deshabilitado con carrito vacío ──────────────────
  testWidgets('botón Cobrar está deshabilitado con carrito vacío',
      (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pump();

    // El ElevatedButton con texto "Cobrar" debe tener onPressed null
    final cobrarBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Cobrar \$0.00 MXN'),
    );
    expect(cobrarBtn.onPressed, isNull);
  });

  // ── CA-03: botón Cobrar muestra total correcto ────────────────────────────
  testWidgets('botón Cobrar muestra el total del carrito', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pump();

    // Añade un producto al carrito vía el provider
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CheckoutScreen)),
    );
    container.read(cartProvider.notifier).addProduct(_makeProduct());
    await tester.pump();

    // El botón debe mostrar el total del producto ($18.00)
    expect(find.textContaining('18.00'), findsWidgets);
  });

  // ── CA-02: añadir producto aparece en el carrito ─────────────────────────
  testWidgets('producto añadido aparece en el carrito', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pump();

    // Añade el producto directamente al provider
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CheckoutScreen)),
    );
    container.read(cartProvider.notifier).addProduct(
          _makeProduct(name: 'Coca-Cola 600ml'),
        );
    await tester.pump();

    // El tile del producto debe ser visible
    expect(find.text('Coca-Cola 600ml'), findsOneWidget);
    // El empty state desaparece
    expect(find.text('Carrito vacío'), findsNothing);
  });

  // ── CA-05: limpiar carrito vuelve al empty state ──────────────────────────
  testWidgets('limpiar carrito restaura el empty state', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pump();

    // Añade producto
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CheckoutScreen)),
    );
    container.read(cartProvider.notifier).addProduct(_makeProduct());
    await tester.pump();

    // Verifica que el producto está en el carrito
    expect(find.text('Coca-Cola 600ml'), findsOneWidget);

    // Limpia directamente el provider (sin dialog para simplificar el test)
    container.read(cartProvider.notifier).clear();
    await tester.pump();

    // El empty state vuelve
    expect(find.text('Carrito vacío'), findsOneWidget);
  });
}
