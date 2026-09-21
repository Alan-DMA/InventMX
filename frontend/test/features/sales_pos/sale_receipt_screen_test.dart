import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/dashboard/data/dashboard_repository.dart';
import 'package:nexus_app/features/dashboard/presentation/dashboard_provider.dart'
    show dashboardRepositoryProvider;
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart';
import 'package:nexus_app/features/management/domain/app_permission.dart';
import 'package:nexus_app/features/management/presentation/management_provider.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_state.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';
import 'package:nexus_app/features/sales_pos/presentation/sale_receipt_screen.dart';
import 'package:nexus_app/features/sales_pos/presentation/widgets/refund_sale_modal.dart';

// ---------------------------------------------------------------------------
// Fase 2 — Acciones sobre la venta: botón "Reembolsar" en el ticket
// ---------------------------------------------------------------------------

CheckoutResult _sale({SaleRefund? refund}) => CheckoutResult(
      saleId: 'sale-1',
      folio: 'NV-2026-000001',
      totalMxn: 89,
      totalPaidMxn: 100,
      changeGivenMxn: 11,
      items: const [
        CartItem(id: 'ci-1', name: 'Coca-Cola 600 ml', unitPriceMxn: 18, quantity: 3),
        CartItem(id: 'ci-2', name: 'Sabritas 45 g', unitPriceMxn: 17, quantity: 2),
      ],
      payments: const [
        PaymentEntry(id: 'p1', method: PaymentMethodMxn.cashMxn, amountMxn: 100),
      ],
      cashierName: 'Eduardo',
      completedAt: DateTime(2026, 9, 17, 12),
      refund: refund,
    );

class _StubSalesRepo implements SalesRepository {
  CheckoutResult? refundedWith;

  @override
  Future<CheckoutResult> checkout({
    required List<CartItem> items,
    required List<PaymentEntry> payments,
    required String cashierName,
    required String warehouseId,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<String>> getCashiers() => throw UnimplementedError();

  @override
  Future<CheckoutResult> getSaleById(String id) => throw UnimplementedError();

  @override
  Future<PaginatedSales> getSales({
    SalesQuery query = const SalesQuery(),
    int page = 1,
    int pageSize = 20,
  }) =>
      throw UnimplementedError();

  @override
  Future<CheckoutResult> refundSale({
    required String saleId,
    required String reason,
    required bool refundToStock,
    List<RefundedLine>? itemsToRefund,
  }) async {
    final sale = _sale();
    final updated = sale.copyWith(
      refund: SaleRefund(
        refundedAt: DateTime(2026, 9, 17, 13),
        reason: reason,
        refundAmountMxn: sale.totalMxn,
        refundToStock: refundToStock,
        lines: sale.items
            .map((i) => RefundedLine(cartItemId: i.id, quantity: i.quantity))
            .toList(),
      ),
    );
    refundedWith = updated;
    return updated;
  }
}

/// Cuenta llamadas a `getProducts` para verificar que `inventoryProvider` se
/// invalida (y por lo tanto vuelve a pedir al backend) tras un reembolso.
class _StubInventoryRepo implements InventoryRepository {
  int getProductsCallCount = 0;

  @override
  Future<PaginatedProducts> getProducts({
    String? query,
    String? category,
    bool lowStock = false,
    int page = 1,
    int pageSize = 20,
  }) async {
    getProductsCallCount++;
    return const PaginatedProducts(
      items: [],
      total: 0,
      page: 1,
      pageSize: 20,
      totalPages: 1,
    );
  }

  @override
  Future<Product> getProductById(String id) => throw UnimplementedError();

  @override
  Future<Product> createProduct({
    required String name,
    required double priceMxn,
    int stock = 0,
    String? category,
    String? barcode,
    double? costMxn,
    int? minStockAlert,
    String? imageUrl,
    String? supplierId,
  }) =>
      throw UnimplementedError();

  @override
  Future<Product> updateProduct({
    required String productId,
    String? name,
    double? priceMxn,
    double? costMxn,
    String? category,
    String? barcode,
    int? minStockAlert,
    String? imageUrl,
    bool? isActive,
    String? supplierId,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> getSuppliers() => throw UnimplementedError();

  @override
  Future<String> uploadProductImage({
    required List<int> fileBytes,
    required String fileName,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> adjustStock({
    required String productId,
    required String movementType,
    required int quantity,
    required String reason,
    String? warehouseId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required int quantity,
    String? notes,
  }) =>
      throw UnimplementedError();

  @override
  Future<PaginatedMovements> getMovements({
    required String productId,
    String? movementType,
    DateTime? dateFrom,
    DateTime? dateTo,
    int page = 1,
    int pageSize = 20,
  }) =>
      throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester, {
  required CheckoutResult result,
  required bool isLookup,
  bool canRefund = false,
  SalesRepository? repo,
  InventoryRepository? inventoryRepo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repo != null) salesRepositoryProvider.overrideWithValue(repo),
        dashboardRepositoryProvider.overrideWithValue(DashboardRepositoryMock()),
        if (inventoryRepo != null)
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        hasPermissionProvider(Permissions.ventasEliminar).overrideWithValue(canRefund),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: SaleReceiptScreen(result: result, isLookup: isLookup),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('en el ticket recién cobrado no hay botón de reembolso', (tester) async {
    await _pump(tester, result: _sale(), isLookup: false, canRefund: true);
    expect(find.byKey(const Key('refundSaleButton')), findsNothing);
  });

  testWidgets('en consulta, sin el permiso ventas.eliminar no se ve el botón',
      (tester) async {
    await _pump(tester, result: _sale(), isLookup: true, canRefund: false);
    expect(find.byKey(const Key('refundSaleButton')), findsNothing);
  });

  testWidgets('en consulta, con el permiso, el botón abre la hoja de reembolso',
      (tester) async {
    await _pump(tester, result: _sale(), isLookup: true, canRefund: true);
    expect(find.byKey(const Key('refundSaleButton')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('refundSaleButton')));
    await tester.tap(find.byKey(const Key('refundSaleButton')));
    await tester.pumpAndSettle();
    expect(find.byType(RefundSaleModal), findsOneWidget);
  });

  testWidgets('una venta ya reembolsada muestra el aviso y no el botón',
      (tester) async {
    final refund = SaleRefund(
      refundedAt: DateTime(2026, 9, 17, 13),
      reason: 'Cliente se arrepintió',
      refundAmountMxn: 89,
      refundToStock: true,
      lines: const [
        RefundedLine(cartItemId: 'ci-1', quantity: 3),
        RefundedLine(cartItemId: 'ci-2', quantity: 2),
      ],
    );
    await _pump(
      tester,
      result: _sale(refund: refund),
      isLookup: true,
      canRefund: true,
    );

    expect(find.textContaining('Reembolsada el'), findsOneWidget);
    expect(find.text('Cliente se arrepintió'), findsOneWidget);
    expect(find.byKey(const Key('refundSaleButton')), findsNothing);
  });

  testWidgets('completar el reembolso actualiza el ticket sin salir de la pantalla',
      (tester) async {
    final repo = _StubSalesRepo();
    await _pump(tester, result: _sale(), isLookup: true, canRefund: true, repo: repo);

    await tester.ensureVisible(find.byKey(const Key('refundSaleButton')));
    await tester.tap(find.byKey(const Key('refundSaleButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('refundAllButton')));
    await tester.enterText(
      find.byKey(const Key('refundReasonField')),
      'Producto defectuoso',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRefundButton')));
    await tester.pumpAndSettle();

    expect(repo.refundedWith, isNotNull);
    // La hoja se cerró y el ticket, en la misma pantalla, ya muestra el aviso.
    expect(find.byType(RefundSaleModal), findsNothing);
    expect(find.textContaining('Reembolsada el'), findsOneWidget);
    expect(find.byKey(const Key('refundSaleButton')), findsNothing);
  });

  // ── Regresión: mismo bug que en checkout (Sep 2026) ───────────────────────
  // Un reembolso con reposición a stock cambia el inventario en el backend,
  // pero Inventario/Detalle de producto seguían mostrando el stock cacheado
  // de `inventoryProvider` porque nadie lo invalidaba tras completar el
  // reembolso (a diferencia de `saleDetailProvider`/`salesKardexProvider`,
  // que sí se invalidaban).
  testWidgets('completar el reembolso invalida inventoryProvider para refrescar el stock',
      (tester) async {
    final repo = _StubSalesRepo();
    final inventoryRepo = _StubInventoryRepo();
    await _pump(
      tester,
      result: _sale(),
      isLookup: true,
      canRefund: true,
      repo: repo,
      inventoryRepo: inventoryRepo,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SaleReceiptScreen)),
    );

    // Lee `inventoryProvider` para que exista y quede "watched" — refleja el
    // caso real (Inventario y el ticket de venta comparten el mismo
    // provider vivo dentro de la misma app).
    container.read(inventoryProvider);
    await tester.pumpAndSettle();
    expect(inventoryRepo.getProductsCallCount, 1);

    await tester.ensureVisible(find.byKey(const Key('refundSaleButton')));
    await tester.tap(find.byKey(const Key('refundSaleButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refundAllButton')));
    await tester.enterText(
      find.byKey(const Key('refundReasonField')),
      'Producto defectuoso',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRefundButton')));
    await tester.pumpAndSettle();

    // El reembolso invalidó inventoryProvider — leerlo de nuevo dispara una
    // segunda llamada real a `getProducts` en vez de servir el caché viejo.
    container.read(inventoryProvider);
    await tester.pumpAndSettle();
    expect(inventoryRepo.getProductsCallCount, 2);
  });
}
