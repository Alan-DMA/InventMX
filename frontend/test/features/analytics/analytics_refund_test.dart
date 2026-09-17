import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/analytics/data/analytics_dashboard_repository.dart';
import 'package:nexus_app/features/analytics/domain/analytics_dashboard.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_state.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';

// ---------------------------------------------------------------------------
// Fase 2 — Acciones sobre la venta: Reportes también debe ser neto
//
// `SalesRepositoryMock._todaysSales` es estático (alimenta Reportes y
// Comisiones sin pasar por Riverpod) — este archivo corre solo para no
// heredar ventas de otros tests dentro del mismo proceso.
// ---------------------------------------------------------------------------

void main() {
  test('un reembolso baja "vendido hoy" y "lo más vendido" exactamente en lo devuelto',
      () async {
    final now = DateTime(2026, 9, 17, 15, 0);
    final salesRepo = SalesRepositoryMock(clock: () => now);
    final analyticsRepo = AnalyticsDashboardRepositoryMock(delay: Duration.zero);

    Future<AnalyticsDashboard> dashboard() => analyticsRepo.getDashboard(
          period: DashboardPeriod.today,
          now: now,
        );

    final before = await dashboard();

    final sale = await salesRepo.checkout(
      items: const [
        CartItem(id: 'ci-1', name: 'Coca-Cola 600 ml', unitPriceMxn: 18, quantity: 20),
      ],
      payments: const [
        PaymentEntry(id: 'p1', method: PaymentMethodMxn.cashMxn, amountMxn: 360),
      ],
      cashierName: 'Eduardo',
    );

    final afterCheckout = await dashboard();
    expect(afterCheckout.totalRevenueMxn, closeTo(before.totalRevenueMxn + 360, 0.001));

    // Reembolso parcial: 3 de las 20 unidades ($54).
    await salesRepo.refundSale(
      saleId: sale.saleId,
      reason: 'Cliente se arrepintió de tres piezas',
      refundToStock: true,
      itemsToRefund: const [RefundedLine(cartItemId: 'ci-1', quantity: 3)],
    );

    final afterRefund = await dashboard();
    // El ingreso del día baja exactamente los $54 reembolsados.
    expect(
      afterRefund.totalRevenueMxn,
      closeTo(afterCheckout.totalRevenueMxn - 54, 0.001),
    );

    // "Lo más vendido" también neto: 17 unidades cuentan, no las 20 vendidas.
    final coca = afterRefund.topProducts.firstWhere((p) => p.name == 'Coca-Cola 600 ml');
    expect(coca.unitsSold, 17);
  });
}
