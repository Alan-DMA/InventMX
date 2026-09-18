import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_app/core/router/app_router.dart' show AppRoutes;
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/saas_admin/domain/subscription.dart' show mxn;
import 'package:nexus_app/features/saas_admin/presentation/saas_provider.dart'
    show clockProvider;
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_state.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';
import 'package:nexus_app/features/sales_pos/domain/sale_summary.dart';
import 'package:nexus_app/features/sales_pos/presentation/sale_receipt_screen.dart';
import 'package:nexus_app/features/sales_pos/presentation/sales_kardex_screen.dart';

// ---------------------------------------------------------------------------
// Fase 2 — Kardex de ventas (CA-01 … CA-06)
// ---------------------------------------------------------------------------

final _now = DateTime(2026, 9, 17, 15, 30);

CheckoutResult _sale({
  required int n,
  required DateTime at,
  String cashier = 'María Hernández',
  List<PaymentEntry>? payments,
  int qty = 1,
}) {
  final items = [
    CartItem(id: 'ci-$n', name: 'Producto $n', unitPriceMxn: 10.0 * n, quantity: qty),
  ];
  final total = items.fold<double>(0, (a, i) => a + i.subtotalMxn);
  final pays = payments ??
      [PaymentEntry(id: 'pe-$n', method: PaymentMethodMxn.cashMxn, amountMxn: total)];
  return CheckoutResult(
    saleId: 'sale-$n',
    folio: 'NV-2026-${n.toString().padLeft(6, '0')}',
    totalMxn: total,
    totalPaidMxn: pays.fold<double>(0, (a, p) => a + p.amountMxn),
    changeGivenMxn: 0,
    items: items,
    payments: pays,
    cashierName: cashier,
    completedAt: at,
  );
}

/// Repositorio en memoria sin retardos: controla el dataset, cuenta llamadas
/// y puede fallar a voluntad.
class _FakeSalesRepo implements SalesRepository {
  _FakeSalesRepo(this.sales);

  List<CheckoutResult> sales;
  int getSalesCalls = 0;
  bool failNext = false;

  @override
  Future<CheckoutResult> checkout({
    required List<CartItem> items,
    required List<PaymentEntry> payments,
    required String cashierName,
    required String warehouseId,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<String>> getCashiers() async =>
      {for (final s in sales) s.cashierName}.toList()..sort();

  @override
  Future<CheckoutResult> refundSale({
    required String saleId,
    required String reason,
    required bool refundToStock,
    List<RefundedLine>? itemsToRefund,
  }) =>
      throw UnimplementedError();

  @override
  Future<CheckoutResult> getSaleById(String id) async =>
      sales.firstWhere((s) => s.saleId == id,
          orElse: () => throw SaleNotFoundException(id));

  @override
  Future<PaginatedSales> getSales({
    SalesQuery query = const SalesQuery(),
    int page = 1,
    int pageSize = 20,
  }) async {
    getSalesCalls++;
    if (failNext) {
      failNext = false;
      throw Exception('sin red');
    }
    final all = sales.where((s) {
      if (query.paymentKind != null &&
          SalePaymentKind.fromPayments(s.payments) != query.paymentKind) {
        return false;
      }
      if (query.cashierName != null && s.cashierName != query.cashierName) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <CheckoutResult>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return PaginatedSales(
      items: items.map(SaleSummary.fromCheckout).toList(),
      total: all.length,
      totalAmountMxn: all.fold<double>(0, (a, s) => a + s.netTotalMxn),
      page: page,
      pageSize: pageSize,
      totalPages: all.isEmpty ? 1 : (all.length / pageSize).ceil(),
    );
  }
}

Future<void> _pump(WidgetTester tester, _FakeSalesRepo repo) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: AppRoutes.salesHistory,
    routes: [
      GoRoute(
        path: AppRoutes.sales,
        builder: (_, __) => const Scaffold(body: Text('POS')),
      ),
      GoRoute(
        path: AppRoutes.salesHistory,
        builder: (_, __) => const SalesKardexScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                SaleLookupScreen(saleId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => _now),
        salesRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

List<CheckoutResult> _threeDays() => [
      _sale(n: 3, at: _now.subtract(const Duration(minutes: 5)), qty: 3),
      _sale(
        n: 2,
        at: _now.subtract(const Duration(days: 1, hours: 2)),
        cashier: 'José Luis Ramírez',
        payments: const [
          PaymentEntry(id: 'x', method: PaymentMethodMxn.cardTpv, amountMxn: 20),
        ],
      ),
      _sale(n: 1, at: _now.subtract(const Duration(days: 3))),
    ];

void main() {
  testWidgets('CA-01 · renglones con hora, total, pago, cajero y folio bajo su día',
      (tester) async {
    await _pump(tester, _FakeSalesRepo(_threeDays()));

    expect(find.text('Historial de ventas'), findsOneWidget);
    expect(find.text('HOY'), findsOneWidget);
    expect(find.text('AYER'), findsOneWidget);
    expect(find.text('LUNES 14 SEP'), findsOneWidget);

    // La de hoy: 15:25, 3 × $30 = $90.00, 3 pzas, efectivo, folio.
    expect(find.text('15:25'), findsOneWidget);
    expect(find.text('\$90.00'), findsOneWidget);
    expect(find.text('3 pzas'), findsOneWidget);
    expect(find.text('Efectivo · María Hernández'), findsNWidgets(2));
    expect(find.text('NV-2026-000003'), findsOneWidget);
    // La de ayer con tarjeta.
    expect(find.text('Tarjeta · José Luis Ramírez'), findsOneWidget);

    // Resumen del recorte completo.
    expect(find.text('3 ventas'), findsOneWidget);
    expect(find.text('\$120.00'), findsOneWidget);
  });

  testWidgets('CA-03 · filtro por forma de pago recorta lista y resumen; limpiar restaura',
      (tester) async {
    await _pump(tester, _FakeSalesRepo(_threeDays()));

    await tester.tap(find.byKey(const Key('salesFiltersButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('paymentKindFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tarjeta').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('activeFiltersBadge')), findsOneWidget);
    expect(find.text('1 venta'), findsOneWidget);
    expect(find.text('\$20.00'), findsWidgets);
    expect(find.text('NV-2026-000003'), findsNothing);
    expect(find.text('NV-2026-000002'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clearSalesFilters')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activeFiltersBadge')), findsNothing);
    expect(find.text('3 ventas'), findsOneWidget);
  });

  testWidgets('vacío con filtros ofrece limpiar; vacío sin filtros ofrece ir a vender',
      (tester) async {
    final repo = _FakeSalesRepo([
      _sale(n: 1, at: _now.subtract(const Duration(hours: 1))),
    ]);
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('salesFiltersButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paymentKindFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SPEI').last);
    await tester.pumpAndSettle();

    expect(find.text('Sin ventas con\nestos filtros'), findsOneWidget);
    await tester.tap(find.byKey(const Key('emptyClearFilters')));
    await tester.pumpAndSettle();
    expect(find.text('NV-2026-000001'), findsOneWidget);

    // Sin ventas en absoluto.
    repo.sales = [];
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Aún no hay ventas\nregistradas'), findsOneWidget);
    await tester.tap(find.byKey(const Key('emptyGoSell')));
    await tester.pumpAndSettle();
    expect(find.text('POS'), findsOneWidget);
  });

  testWidgets('error de carga: mensaje y reintentar vuelve a pedir', (tester) async {
    final repo = _FakeSalesRepo(_threeDays())..failNext = true;
    await _pump(tester, repo);

    expect(find.text('No se pudieron cargar\nlas ventas'), findsOneWidget);
    await tester.tap(find.byKey(const Key('salesRetry')));
    await tester.pumpAndSettle();
    expect(find.text('NV-2026-000003'), findsOneWidget);
    expect(repo.getSalesCalls, 2);
  });

  testWidgets('CA-04/CA-05 · tocar un renglón abre el ticket en modo consulta y al volver la lista conserva scroll sin recargar',
      (tester) async {
    // 45 ventas: dos páginas y suficiente alto para desplazarse.
    final sales = [
      for (var i = 45; i >= 1; i--)
        _sale(n: i, at: _now.subtract(Duration(minutes: 3 * (46 - i)))),
    ];
    final repo = _FakeSalesRepo(sales);
    await _pump(tester, repo);
    expect(repo.getSalesCalls, 1);

    // CA-02 · scroll infinito: al fondo de la primera página pide la segunda.
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(repo.getSalesCalls, 2);

    final scrollable = find.descendant(
      of: find.byType(SalesKardexScreen),
      matching: find.byType(Scrollable),
    );
    final offsetBefore = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offsetBefore, greaterThan(0));

    // Un renglón visible de la segunda mitad.
    final row = find.byKey(const Key('saleRow-sale-20'));
    await tester.scrollUntilVisible(row, 120, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(SaleReceiptScreen), findsOneWidget);
    expect(find.text('NV-2026-000020'), findsWidgets);
    expect(find.text('¡Venta registrada!'), findsNothing);
    expect(find.text('Nueva Venta'), findsNothing);
    expect(find.text('WhatsApp'), findsOneWidget);

    final calls = repo.getSalesCalls;
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(SalesKardexScreen), findsOneWidget);
    expect(repo.getSalesCalls, calls);
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
    );
    expect(row, findsOneWidget);
  });

  testWidgets('CA-06 · al volver a abrir el kardex se vuelve a pedir la lista',
      (tester) async {
    final repo = _FakeSalesRepo(_threeDays());
    await _pump(tester, repo);
    expect(repo.getSalesCalls, 1);

    // Sale del kardex por completo (a vender) y regresa.
    await tester.tap(find.byKey(const Key('salesFiltersButton')));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(SalesKardexScreen));
    GoRouter.of(ctx).go(AppRoutes.sales);
    await tester.pumpAndSettle();
    expect(find.text('POS'), findsOneWidget);

    repo.sales = [..._threeDays(), _sale(n: 9, at: _now)];
    GoRouter.of(tester.element(find.text('POS'))).go(AppRoutes.salesHistory);
    await tester.pumpAndSettle();

    expect(repo.getSalesCalls, 2);
    expect(find.text('NV-2026-000009'), findsOneWidget);
  });

  testWidgets('una venta reembolsada se ve atenuada, con etiqueta y el resumen es neto',
      (tester) async {
    final refunded = _sale(n: 1, at: _now.subtract(const Duration(minutes: 5)));
    final refundedWithRefund = CheckoutResult(
      saleId: refunded.saleId,
      folio: refunded.folio,
      totalMxn: refunded.totalMxn,
      totalPaidMxn: refunded.totalPaidMxn,
      changeGivenMxn: refunded.changeGivenMxn,
      items: refunded.items,
      payments: refunded.payments,
      cashierName: refunded.cashierName,
      completedAt: refunded.completedAt,
      refund: SaleRefund(
        refundedAt: _now,
        reason: 'Cliente se arrepintió',
        refundAmountMxn: refunded.totalMxn,
        refundToStock: true,
        lines: const [],
      ),
    );
    final other = _sale(n: 2, at: _now.subtract(const Duration(hours: 1)));
    final repo = _FakeSalesRepo([refundedWithRefund, other]);
    await _pump(tester, repo);

    // Etiqueta visible y renglón atenuado.
    expect(find.text('Reembolsada'), findsOneWidget);
    final opacityFinder = find.ancestor(
      of: find.byKey(Key('saleRow-${refundedWithRefund.saleId}')),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(opacityFinder.first).opacity, lessThan(1));

    // El resumen es neto: sólo cuenta la venta no reembolsada.
    expect(find.text('2 ventas'), findsOneWidget);
    expect(find.text(mxn(other.totalMxn)), findsWidgets);
  });
}
