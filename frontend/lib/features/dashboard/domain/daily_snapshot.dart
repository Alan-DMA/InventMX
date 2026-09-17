import 'package:equatable/equatable.dart';

import 'stock_alert.dart';

/// Estado del negocio **hoy** — lo que el Centro de mando resume de un
/// vistazo (SR-02, N-08).
///
/// A propósito no trae series ni históricos: eso es Reportes (Tarea 15.2.3).
/// Aquí sólo va lo accionable del día.
class DailySnapshot extends Equatable {
  const DailySnapshot({
    required this.salesTodayMxn,
    required this.salesTodayCount,
    required this.salesYesterdayMxn,
    required this.marginTodayMxn,
    required this.lowStockCount,
    required this.outOfStockCount,
    this.lowStockAlerts = const [],
    required this.payablesDueMxn,
    required this.payablesOverdueCount,
    required this.isCashSessionOpen,
    required this.cashExpectedMxn,
  });

  final double salesTodayMxn;
  final int salesTodayCount;

  /// Sirve sólo para la comparación "vs ayer" de la tarjeta de ventas.
  final double salesYesterdayMxn;

  /// Utilidad bruta del día. Mock simple junto a ventas — Reportes ya calcula
  /// margen real desde `AnalyticsDashboard` (`grossProfitMxn`); aquí se
  /// documenta como pendiente del mismo endpoint (`GET /analytics/dashboard`).
  final double marginTodayMxn;

  final int lowStockCount;
  final int outOfStockCount;

  /// Renglones concretos para las alertas en línea (Fase 3). Autocontenido
  /// en el mock del Dashboard — ver `StockAlertItem`.
  final List<StockAlertItem> lowStockAlerts;

  /// Total por pagar a proveedores que ya venció o vence hoy.
  final double payablesDueMxn;
  final int payablesOverdueCount;

  final bool isCashSessionOpen;
  final double cashExpectedMxn;

  /// Variación contra ayer, en porcentaje. `null` si ayer no hubo ventas
  /// (dividir entre cero no dice nada útil al tendero).
  double? get salesDeltaPercent {
    if (salesYesterdayMxn <= 0) return null;
    return ((salesTodayMxn - salesYesterdayMxn) / salesYesterdayMxn) * 100;
  }

  /// Margen como % de lo vendido hoy. `null` si no hubo ventas.
  double? get marginTodayPercent {
    if (salesTodayMxn <= 0) return null;
    return (marginTodayMxn / salesTodayMxn) * 100;
  }

  int get stockAlertCount => lowStockCount + outOfStockCount;

  @override
  List<Object?> get props => [
        salesTodayMxn,
        salesTodayCount,
        salesYesterdayMxn,
        marginTodayMxn,
        lowStockCount,
        outOfStockCount,
        lowStockAlerts,
        payablesDueMxn,
        payablesOverdueCount,
        isCashSessionOpen,
        cashExpectedMxn,
      ];
}
