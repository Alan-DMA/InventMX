/// Modelo de dominio — Dashboard analítico del negocio (RF-20, RF-21, SR-02).
///
/// Se compone en el repositorio a partir de tres lecturas del backend real
/// (`backend/app/modules/analytics_reports`): `GET /analytics/financial-summary`
/// (período actual y anterior), `GET /analytics/inventory-health` (lo más
/// vendido) y `GET /analytics/sales-trends` (serie diaria). Todo en pesos.
///
/// Sin enmarcado de pérdida: la comparativa muestra ambos meses y el cambio
/// como dato; un margen negativo se pinta en rojo como número, no como regaño.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// Período
// ---------------------------------------------------------------------------

/// Rango cerrado de fechas (ambos extremos inclusive, a nivel de día).
typedef DateRange = ({DateTime start, DateTime end});

/// Períodos del dashboard. Son **de calendario** (decisión D2, Sep 2026):
/// "Semana" es lunes→domingo y "Mes" el mes natural, igual que los presets
/// `THIS_WEEK` / `THIS_MONTH` del backend — así "comparado con la semana
/// pasada" es exactamente eso, no "los 7 días anteriores".
enum DashboardPeriod {
  today('TODAY', 'Hoy'),
  week('THIS_WEEK', 'Semana'),
  month('THIS_MONTH', 'Mes');

  const DashboardPeriod(this.preset, this.label);

  /// Valor del query param `preset` de `/analytics/*`.
  final String preset;
  final String label;

  /// Rango del período que contiene a [now].
  DateRange range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      DashboardPeriod.today => (start: today, end: today),
      DashboardPeriod.week => (
          start: today.subtract(Duration(days: today.weekday - 1)),
          end: today.add(Duration(days: DateTime.daysPerWeek - today.weekday)),
        ),
      DashboardPeriod.month => (
          start: DateTime(today.year, today.month, 1),
          end: DateTime(today.year, today.month + 1, 0),
        ),
    };
  }

  /// Período inmediatamente anterior, del mismo tipo (ayer / semana pasada /
  /// mes pasado). Es la base de la comparativa.
  DateRange previousRange(DateTime now) {
    final current = range(now);
    return switch (this) {
      DashboardPeriod.today => (
          start: current.start.subtract(const Duration(days: 1)),
          end: current.start.subtract(const Duration(days: 1)),
        ),
      DashboardPeriod.week => (
          start: current.start.subtract(const Duration(days: 7)),
          end: current.start.subtract(const Duration(days: 1)),
        ),
      DashboardPeriod.month => (
          start: DateTime(current.start.year, current.start.month - 1, 1),
          end: DateTime(current.start.year, current.start.month, 0),
        ),
    };
  }

  String get currentLabel => switch (this) {
        DashboardPeriod.today => 'Hoy',
        DashboardPeriod.week => 'Esta semana',
        DashboardPeriod.month => 'Este mes',
      };

  String get previousLabel => switch (this) {
        DashboardPeriod.today => 'Ayer',
        DashboardPeriod.week => 'Semana pasada',
        DashboardPeriod.month => 'Mes pasado',
      };
}

// ---------------------------------------------------------------------------
// Piezas
// ---------------------------------------------------------------------------

/// Un punto de la serie de ventas (un día natural).
class DailySalesPoint extends Equatable {
  const DailySalesPoint({
    required this.date,
    required this.revenueMxn,
    required this.ordersCount,
  });

  final DateTime date;
  final double revenueMxn;
  final int ordersCount;

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

  /// Piezas netas (vendidas − devueltas). El backend maneja decimales para
  /// productos a granel; aquí se redondea porque el Top se lee en piezas.
  final int unitsSold;
  final double revenueMxn;
  final double profitMxn;

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

/// Cuánto de lo cobrado entró por cada método (`payment_methods` de
/// `/analytics/financial-summary`). Responde "¿cuánto tengo en efectivo
/// físico y cuánto en el banco?" — sección "Cómo te pagan" (Fase B).
class PaymentMethodShare extends Equatable {
  const PaymentMethodShare({
    required this.method,
    required this.totalMxn,
    required this.transactionCount,
    required this.percentage,
  });

  /// Código del backend (`CASH_MXN`, `CARD_TPV`, `SPEI`, `CODI`, …).
  final String method;
  final double totalMxn;
  final int transactionCount;

  /// Sobre el total cobrado (los % suman 100).
  final double percentage;

  /// Nombre en lenguaje de tendero.
  String get label => switch (method) {
        'CASH_MXN' || 'CASH' => 'Efectivo',
        'CARD_TPV' || 'CARD' => 'Tarjeta',
        'SPEI' || 'TRANSFER' => 'Transferencia',
        'CODI' => 'CoDi',
        'CREDIT' => 'Crédito',
        _ => 'Otro',
      };

  bool get isCash => method == 'CASH_MXN' || method == 'CASH';

  @override
  List<Object?> get props => [method, totalMxn, transactionCount, percentage];
}

/// "Tu dinero hoy" (`/analytics/working-capital`): lo que hay en caja menos
/// lo que debes a proveedores (más cuentas por cobrar, si el backend las
/// mandara — la app no vende fiado). No depende del período: es una foto de hoy.
///
/// Sin *loss framing*: una deuda con proveedores es un dato con signo, no un
/// regaño; el neto negativo se pinta en rojo como número.
class WorkingCapital extends Equatable {
  const WorkingCapital({
    required this.asOf,
    required this.cashInRegisterMxn,
    required this.receivableMxn,
    required this.payableMxn,
    required this.netMxn,
  });

  final DateTime asOf;

  /// Fondo de apertura de las cajas abiertas — el backend **no** suma las
  /// ventas del turno (anotado para Alan); en pantalla se llama "Fondo de
  /// caja" para no prometer lo que no es.
  final double cashInRegisterMxn;
  final double receivableMxn;
  final double payableMxn;
  final double netMxn;

  bool get isEmpty =>
      cashInRegisterMxn == 0 && receivableMxn == 0 && payableMxn == 0;

  @override
  List<Object?> get props =>
      [asOf, cashInRegisterMxn, receivableMxn, payableMxn, netMxn];
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
    this.refundsMxn = 0,
    required this.totalOrders,
    required this.averageTicketMxn,
    required this.grossProfitMxn,
    required this.grossMarginPercent,
    required this.dailySales,
    required this.topProducts,
    required this.comparison,
    this.paymentMethods = const [],
    this.workingCapital,
  });

  final DashboardPeriod period;
  final DateTime periodStart;
  final DateTime periodEnd;

  // Ventas netas (bruto − reembolsos), tickets y ticket promedio
  final double totalRevenueMxn;

  /// Lo devuelto en el período. La pantalla lo dice junto al neto para que
  /// el total cuadre con el historial (QA de Eduardo, Sep 21).
  final double refundsMxn;
  double get grossRevenueMxn => totalRevenueMxn + refundsMxn;
  final int totalOrders;
  final double averageTicketMxn;

  // Utilidad bruta con costo congelado al momento de vender (RF-20)
  final double grossProfitMxn;
  final double grossMarginPercent;

  final List<DailySalesPoint> dailySales;
  final List<TopProduct> topProducts;
  final PeriodComparison comparison;

  /// "Cómo te pagan" — vacío si la lectura falló o no hubo cobros.
  final List<PaymentMethodShare> paymentMethods;

  /// "Tu dinero hoy" — null si la lectura falló (la sección no se pinta).
  final WorkingCapital? workingCapital;

  bool get isEmpty => totalOrders == 0 && dailySales.every((d) => d.revenueMxn == 0);

  @override
  List<Object?> get props => [
        period,
        periodStart,
        periodEnd,
        totalRevenueMxn,
        refundsMxn,
        totalOrders,
        averageTicketMxn,
        grossProfitMxn,
        grossMarginPercent,
        dailySales,
        topProducts,
        comparison,
        paymentMethods,
        workingCapital,
      ];
}
