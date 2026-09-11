import '../../sales_pos/data/sales_repository.dart';
import '../../sales_pos/domain/cart_state.dart';
import '../domain/employee_performance.dart';

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

abstract class CommissionsRepository {
  /// Equivalente local a `GET /analytics/commissions` (Tarea 8.1.3, aún
  /// pendiente) filtrado al vendedor en sesión y al período de hoy.
  Future<EmployeePerformance> getPerformance({required String cashierName});
}

// ---------------------------------------------------------------------------
// Mock — activo hasta que Alan complete Tarea 8.1.3 (backend de comisiones)
// ---------------------------------------------------------------------------

class CommissionsRepositoryMock implements CommissionsRepository {
  static const _fakeDelay = Duration(milliseconds: 500);

  /// Tasa dinámica configurable por vendedor (RF-10) — fija en el Mock.
  static const _commissionRatePercent = 5.0;

  /// Vendedores de referencia para poblar el ranking mientras no exista un
  /// backend multi-usuario real (Alan, Tarea 2.1 RBAC / 8.1.3 comisiones).
  static const _peerSeed = [
    ('María López', 62.00),
    ('Juan Torres', 31.50),
  ];

  @override
  Future<EmployeePerformance> getPerformance({
    required String cashierName,
  }) async {
    await Future.delayed(_fakeDelay);

    final mySales = SalesRepositoryMock.todaysSales
        .where((s) => s.cashierName == cashierName)
        .toList();

    final totalSalesMxn =
        mySales.fold(0.0, (sum, s) => sum + s.totalMxn);
    final accumulatedCommissionMxn =
        totalSalesMxn * (_commissionRatePercent / 100);

    final dailyBreakdown = _groupByDay(mySales);

    final ranking = <RankingEntry>[
      RankingEntry(
        cashierName: cashierName,
        commissionMxn: accumulatedCommissionMxn,
        isCurrentUser: true,
      ),
      for (final (name, commissionMxn) in _peerSeed)
        RankingEntry(cashierName: name, commissionMxn: commissionMxn),
    ]..sort((a, b) => b.commissionMxn.compareTo(a.commissionMxn));

    final today = DateTime.now();
    final periodLabel =
        'Hoy · ${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';

    return EmployeePerformance(
      cashierName: cashierName,
      role: 'Vendedor',
      periodLabel: periodLabel,
      totalSalesMxn: totalSalesMxn,
      accumulatedCommissionMxn: accumulatedCommissionMxn,
      commissionRatePercent: _commissionRatePercent,
      dailyBreakdown: dailyBreakdown,
      ranking: ranking,
    );
  }

  List<DailyCommissionEntry> _groupByDay(List<CheckoutResult> sales) {
    final byDay = <DateTime, List<CheckoutResult>>{};
    for (final sale in sales) {
      final day = DateTime(
        sale.completedAt.year,
        sale.completedAt.month,
        sale.completedAt.day,
      );
      byDay.putIfAbsent(day, () => []).add(sale);
    }

    final entries = byDay.entries.map((entry) {
      final daySalesTotal =
          entry.value.fold(0.0, (sum, s) => sum + s.totalMxn);
      return DailyCommissionEntry(
        date: entry.key,
        salesCount: entry.value.length,
        commissionMxn: daySalesTotal * (_commissionRatePercent / 100),
      );
    }).toList();

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }
}
