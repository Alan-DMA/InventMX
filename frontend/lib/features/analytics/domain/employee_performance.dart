import 'package:equatable/equatable.dart';

/// Esquema de comisión del empleado (RF-10). Mismo enum que el backend
/// (`commission_type_enum`): la tasa se lee según el tipo.
enum CommissionType {
  percentageSale('PERCENTAGE_SALE'),
  percentageProfit('PERCENTAGE_PROFIT'),
  fixedPerSale('FIXED_PER_SALE');

  const CommissionType(this.apiValue);
  final String apiValue;

  static CommissionType fromApi(String? value) => values.firstWhere(
        (t) => t.apiValue == value,
        orElse: () => CommissionType.percentageSale,
      );

  /// Texto de la tarjeta "Tasa": "5% sobre ventas", "10% sobre utilidad",
  /// "\$15.00 por ticket".
  String describe(double rate) => switch (this) {
        CommissionType.percentageSale => '${_pct(rate)} sobre ventas',
        CommissionType.percentageProfit => '${_pct(rate)} sobre utilidad',
        CommissionType.fixedPerSale => '\$${rate.toStringAsFixed(2)} por ticket',
      };

  static String _pct(double rate) =>
      '${rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toStringAsFixed(2)}%';
}

/// Comisiones generadas por el vendedor en un día del período consultado.
///
/// Trazabilidad: Doc. Maestro RF-10 (Sección 5.2) · `docs/api/analytics.yaml`
/// (`GET /analytics/commissions`, `commission_details[]` agregado por día).
class DailyCommissionEntry extends Equatable {
  const DailyCommissionEntry({
    required this.date,
    required this.salesCount,
    required this.commissionMxn,
  });

  final DateTime date;
  final int salesCount;
  final double commissionMxn;

  @override
  List<Object?> get props => [date, salesCount, commissionMxn];
}

/// Un mes del histórico personal de comisiones (últimos 6 meses).
///
/// Sustituye al ranking (QA de Eduardo, Sep 21): las comisiones de los
/// demás son dato privado de cada vendedor; lo que sí sirve es compararse
/// con uno mismo mes a mes.
class MonthlyCommissionEntry extends Equatable {
  const MonthlyCommissionEntry({
    required this.month,
    required this.salesCount,
    required this.commissionMxn,
  });

  /// Primer día del mes (sólo cuentan año y mes).
  final DateTime month;
  final int salesCount;
  final double commissionMxn;

  @override
  List<Object?> get props => [month, salesCount, commissionMxn];
}

/// Snapshot de rendimiento/comisiones de un vendedor — Tarea 8.2.3.
///
/// Alimentado por `GET /analytics/commissions?period_month=YYYY-MM` real
/// (Sep 2026): `current_user` (tasa y esquema vigentes), `summary`,
/// `daily_breakdown[]` e `history[]` — todo del usuario en sesión; el
/// servidor no expone comisiones ajenas.
///
/// Trazabilidad: Doc. Maestro RF-10, Sección 6 (SR-05) · HU-14 / CU-16
class EmployeePerformance extends Equatable {
  const EmployeePerformance({
    required this.cashierName,
    required this.role,
    required this.periodLabel,
    required this.totalSalesMxn,
    required this.accumulatedCommissionMxn,
    required this.commissionRatePercent,
    this.commissionType = CommissionType.percentageSale,
    required this.dailyBreakdown,
    this.history = const [],
  });

  final String cashierName;
  final String role;

  /// Etiqueta legible del período consultado (ej. "Hoy · 10 sep 2026").
  final String periodLabel;

  final double totalSalesMxn;
  final double accumulatedCommissionMxn;
  /// Tasa vigente del empleado: porcentaje o monto fijo según [commissionType].
  final double commissionRatePercent;
  final CommissionType commissionType;

  /// Sin esquema configurado (tasa 0) el tablero lo dice en vez de mostrar 0 %.
  bool get hasCommissionScheme => commissionRatePercent > 0;

  final List<DailyCommissionEntry> dailyBreakdown;

  /// Últimos 6 meses del propio vendedor, del más reciente al más viejo.
  final List<MonthlyCommissionEntry> history;

  @override
  List<Object?> get props => [
        cashierName,
        role,
        periodLabel,
        totalSalesMxn,
        accumulatedCommissionMxn,
        commissionRatePercent,
        commissionType,
        dailyBreakdown,
        history,
      ];
}
