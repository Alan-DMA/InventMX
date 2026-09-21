/// Modelo de dominio — Dashboard analítico del negocio (RF-20, RF-21, SR-02).
///
/// Anclado a `GET /analytics/dashboard` (sales_metrics, profitability,
/// top_products) y a la serie diaria de `GET /analytics/sales-trends`
/// (docs/api/analytics.yaml). Todo en pesos mexicanos.
///
/// Sin enmarcado de pérdida: la comparativa muestra ambos meses y el cambio
/// como dato; un margen negativo se pinta en rojo como número, no como regaño.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// Período
// ---------------------------------------------------------------------------

enum DashboardPeriod {
  today('TODAY', 'Hoy'),
  week('WEEK', 'Semana'),
  month('MONTH', 'Mes');

  const DashboardPeriod(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

// ---------------------------------------------------------------------------
// Piezas
// ---------------------------------------------------------------------------

/// Un punto de la serie de ventas (un día).
class DailySalesPoint extends Equatable {
  const DailySalesPoint({
    required this.date,
    required this.revenueMxn,
    required this.ordersCount,
  });

  final DateTime date;
  final double revenueMxn;
  final int ordersCount;

  factory DailySalesPoint.fromJson(Map<dynamic, dynamic> json) => DailySalesPoint(
        date: DateTime.tryParse(json['period']?.toString() ?? '') ?? DateTime.now(),
        revenueMxn: _d(json['revenue_mxn']),
        ordersCount: _i(json['orders_count']),
      );

  @override
  List<Object?> get props => [date, revenueMxn, ordersCount];
}

/// Producto en el Top del período.
class TopProduct extends Equatable {
  const TopProduct({
    required this.name,
    required this.unitsSold,
    required this.revenueMxn,
    required this.profitMxn,
  });

  final String name;
  final int unitsSold;
  final double revenueMxn;
  final double profitMxn;

  factory TopProduct.fromJson(Map<dynamic, dynamic> json) => TopProduct(
        name: (json['product_name'] ?? json['name'] ?? '').toString(),
        unitsSold: _i(json['units_sold']),
        revenueMxn: _d(json['revenue_mxn']),
        profitMxn: _d(json['profit_mxn']),
      );

  @override
  List<Object?> get props => [name, unitsSold, revenueMxn, profitMxn];
}

/// Comparativa contra el período anterior (mismo tamaño).
class PeriodComparison extends Equatable {
  const PeriodComparison({
    required this.currentLabel,
    required this.previousLabel,
    required this.currentRevenueMxn,
    required this.previousRevenueMxn,
  });

  final String currentLabel;
  final String previousLabel;
  final double currentRevenueMxn;
  final double previousRevenueMxn;

  /// Cambio porcentual. Null cuando no hay base de comparación (anterior = 0).
  double? get changePercent => previousRevenueMxn <= 0
      ? null
      : (currentRevenueMxn - previousRevenueMxn) / previousRevenueMxn * 100;

  @override
  List<Object?> get props =>
      [currentLabel, previousLabel, currentRevenueMxn, previousRevenueMxn];
}

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

class AnalyticsDashboard extends Equatable {
  const AnalyticsDashboard({
    required this.period,
    required this.periodStart,
    required this.periodEnd,
    required this.totalRevenueMxn,
    required this.totalOrders,
    required this.averageTicketMxn,
    required this.grossProfitMxn,
    required this.grossMarginPercent,
    required this.dailySales,
    required this.topProducts,
    required this.comparison,
  });

  final DashboardPeriod period;
  final DateTime periodStart;
  final DateTime periodEnd;

  // sales_metrics
  final double totalRevenueMxn;
  final int totalOrders;
  final double averageTicketMxn;

  // profitability — utilidad bruta con costo congelado (RF-20)
  final double grossProfitMxn;
  final double grossMarginPercent;

  final List<DailySalesPoint> dailySales;
  final List<TopProduct> topProducts;
  final PeriodComparison comparison;

  bool get isEmpty => totalOrders == 0 && dailySales.every((d) => d.revenueMxn == 0);

  /// Mapea `GET /analytics/dashboard` + la serie de `sales-trends`.
  factory AnalyticsDashboard.fromJson(
    Map<dynamic, dynamic> json, {
    required DashboardPeriod period,
    List<dynamic> trends = const [],
  }) {
    final info = (json['period_info'] as Map?) ?? const {};
    final sales = (json['sales_metrics'] as Map?) ?? const {};
    final profit = (json['profitability'] as Map?) ?? const {};
    final top = (json['top_products'] as List?) ?? const [];
    final start = DateTime.tryParse(info['start_date']?.toString() ?? '') ?? DateTime.now();
    final end = DateTime.tryParse(info['end_date']?.toString() ?? '') ?? DateTime.now();
    final current = _d(sales['total_revenue_mxn']);
    final changeVal = _d(sales['revenue_change_percent']);
    final hasChange = sales['revenue_change_percent'] != null;
    final previous = hasChange && changeVal != -100
        ? current / (1 + changeVal / 100)
        : 0.0;

    return AnalyticsDashboard(
      period: period,
      periodStart: start,
      periodEnd: end,
      totalRevenueMxn: current,
      totalOrders: _i(sales['total_orders']),
      averageTicketMxn: _d(sales['average_ticket_mxn']),
      grossProfitMxn: _d(profit['gross_profit_mxn']),
      grossMarginPercent: _d(profit['gross_margin_percent']),
      dailySales: trends.whereType<Map>().map(DailySalesPoint.fromJson).toList(),
      topProducts: top.whereType<Map>().map(TopProduct.fromJson).toList(),
      comparison: PeriodComparison(
        currentLabel: 'Este período',
        previousLabel: 'Período anterior',
        currentRevenueMxn: current,
        previousRevenueMxn: previous,
      ),
    );
  }

  @override
  List<Object?> get props => [
        period,
        periodStart,
        periodEnd,
        totalRevenueMxn,
        totalOrders,
        averageTicketMxn,
        grossProfitMxn,
        grossMarginPercent,
        dailySales,
        topProducts,
        comparison,
      ];
}

double _d(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0.0;
}

int _i(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  return int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? 0;
}
