import 'package:equatable/equatable.dart';

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

/// Fila del ranking de vendedores por comisión generada en el período.
class RankingEntry extends Equatable {
  const RankingEntry({
    required this.cashierName,
    required this.commissionMxn,
    this.isCurrentUser = false,
  });

  final String cashierName;
  final double commissionMxn;
  final bool isCurrentUser;

  @override
  List<Object?> get props => [cashierName, commissionMxn, isCurrentUser];
}

/// Snapshot de rendimiento/comisiones de un vendedor — Tarea 8.2.3.
///
/// Modelado sobre la forma de `GET /analytics/commissions` (un elemento de
/// `data.cashiers[]` más el desglose diario derivado de
/// `commission_details[]`), aunque hoy se alimenta de un Mock local mientras
/// Alan no entrega la Tarea 8.1.3.
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
    required this.dailyBreakdown,
    required this.ranking,
  });

  final String cashierName;
  final String role;

  /// Etiqueta legible del período consultado (ej. "Hoy · 10 sep 2026").
  final String periodLabel;

  final double totalSalesMxn;
  final double accumulatedCommissionMxn;
  final double commissionRatePercent;

  final List<DailyCommissionEntry> dailyBreakdown;
  final List<RankingEntry> ranking;

  @override
  List<Object?> get props => [
        cashierName,
        role,
        periodLabel,
        totalSalesMxn,
        accumulatedCommissionMxn,
        commissionRatePercent,
        dailyBreakdown,
        ranking,
      ];
}
