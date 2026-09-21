import 'package:equatable/equatable.dart';

import 'pending_purchase_alert.dart';
import 'stock_alert.dart';

/// Estado del negocio **hoy** — lo que el Centro de mando resume de un
/// vistazo (SR-02, N-08).
///
/// Soporta tanto el contrato de endpoints en vivo (`GET /api/v1/analytics/dashboard`)
/// como datos de pruebas y mocks deterministas.
class DailySnapshot extends Equatable {
  const DailySnapshot({
    required this.salesTodayMxn,
    required this.salesTodayCount,
    required this.salesYesterdayMxn,
    required this.marginTodayMxn,
    required this.lowStockCount,
    required this.outOfStockCount,
    this.lowStockAlerts = const [],
    this.pendingPurchasesAlerts = const [],
    this.revenueChangePercent,
    this.marginChangePercent,
    required this.payablesDueMxn,
    required this.payablesOverdueCount,
    required this.isCashSessionOpen,
    required this.cashExpectedMxn,
  });

  /// Venta neta cobrada hoy en Pesos Mexicanos
  final double salesTodayMxn;

  /// Número de tickets/transacciones cobradas hoy
  final int salesTodayCount;

  /// Venta de ayer para comparación
  final double salesYesterdayMxn;

  /// Utilidad bruta del día (Ventas Netas - Costo de lo Vendido)
  final double marginTodayMxn;

  /// Cantidad de productos con existencias por debajo del mínimo
  final int lowStockCount;

  /// Cantidad de productos con stock en cero
  final int outOfStockCount;

  /// Lista de productos con alerta crítica de stock
  final List<StockAlertItem> lowStockAlerts;

  /// Lista de órdenes de compra pendientes o vencidas
  final List<PendingPurchaseAlert> pendingPurchasesAlerts;

  /// Alias de conveniencia para la lista de órdenes de compra pendientes
  List<PendingPurchaseAlert> get pendingPurchaseAlerts => pendingPurchasesAlerts;

  /// Cambio porcentual de ventas provisto directamente por el backend
  final double? revenueChangePercent;

  /// Cambio porcentual de margen provisto directamente por el backend
  final double? marginChangePercent;

  /// Total por pagar a proveedores que ya venció o vence hoy
  final double payablesDueMxn;

  /// Cantidad de cuentas por pagar vencidas
  final int payablesOverdueCount;

  /// Indica si hay un turno de caja abierto actualmente
  final bool isCashSessionOpen;

  /// Saldo estimado o esperado en caja
  final double cashExpectedMxn;

  /// Variación contra ayer en porcentaje. Si el backend nos mandó el cálculo
  /// lo usamos directamente; si no, lo calculamos en base a ventas de ayer.
  double? get salesDeltaPercent {
    if (revenueChangePercent != null) return revenueChangePercent;
    if (salesYesterdayMxn <= 0) return null;
    return ((salesTodayMxn - salesYesterdayMxn) / salesYesterdayMxn) * 100;
  }

  /// Variación del margen contra ayer.
  double? get marginDeltaPercent {
    if (marginChangePercent != null) return marginChangePercent;
    return null;
  }

  /// Margen como % de lo vendido hoy. `null` si no hubo ventas.
  double? get marginTodayPercent {
    if (salesTodayMxn <= 0) return null;
    return (marginTodayMxn / salesTodayMxn) * 100;
  }

  /// Total combinado de alertas de stock
  int get stockAlertCount => lowStockCount + outOfStockCount;

  /// Total de alertas activas (stock crítico + órdenes de compra pendientes)
  int get totalAlertsCount => stockAlertCount + pendingPurchasesAlerts.length;

  /// Construye un snapshot en tiempo real a partir del endpoint `GET /api/v1/analytics/dashboard`
  factory DailySnapshot.fromJson(Map<String, dynamic> json) {
    // Resolver si viene envuelto en `data` o plano
    final data = json.containsKey('data') && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;

    final sales = data['sales_metrics'] as Map<String, dynamic>? ?? const {};
    final profit = data['profitability'] as Map<String, dynamic>? ?? const {};
    final inv = data['inventory_metrics'] as Map<String, dynamic>? ?? const {};

    final critList = (data['critical_stock_alerts'] as List<dynamic>?)
            ?.map((e) => StockAlertItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];

    final poList = (data['pending_purchases'] as List<dynamic>?)
            ?.map((e) => PendingPurchaseAlert.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];

    final totalRevenue = _toDouble(sales['total_revenue_mxn']);
    final totalOrders = _toInt(sales['total_orders']);
    final revChange = _toNullableDouble(sales['revenue_change_percent']);

    final grossProfit = _toDouble(profit['gross_profit_mxn']);
    final marginChange = _toNullableDouble(profit['margin_change_percent']);

    final lowAlerts = _toInt(inv['low_stock_alerts'], defaultValue: critList.length);
    final outOfStock = critList.where((c) => c.isOutOfStock).length;

    // Calcular venta de ayer inferida si hay cambio porcentual
    double salesYesterday = 0.0;
    if (revChange != null && revChange != -100.0) {
      salesYesterday = totalRevenue / (1 + (revChange / 100));
    }

    return DailySnapshot(
      salesTodayMxn: totalRevenue,
      salesTodayCount: totalOrders,
      salesYesterdayMxn: salesYesterday,
      marginTodayMxn: grossProfit,
      lowStockCount: lowAlerts,
      outOfStockCount: outOfStock,
      lowStockAlerts: critList,
      pendingPurchasesAlerts: poList,
      revenueChangePercent: revChange,
      marginChangePercent: marginChange,
      payablesDueMxn: poList.fold<double>(0.0, (acc, po) => acc + po.totalMxn),
      payablesOverdueCount: poList.where((po) => po.isOverdue).length,
      isCashSessionOpen: true,
      cashExpectedMxn: totalRevenue,
    );
  }

  @override
  List<Object?> get props => [
        salesTodayMxn,
        salesTodayCount,
        salesYesterdayMxn,
        marginTodayMxn,
        lowStockCount,
        outOfStockCount,
        lowStockAlerts,
        pendingPurchasesAlerts,
        revenueChangePercent,
        marginChangePercent,
        payablesDueMxn,
        payablesOverdueCount,
        isCashSessionOpen,
        cashExpectedMxn,
      ];
}

// ---------------------------------------------------------------------------
// Helpers para parseo numérico tolerante a tipos (num, String de Decimal, null)
// ---------------------------------------------------------------------------

/// Parsea un valor numérico a double de forma segura, ya sea num, String o null.
double _toDouble(dynamic v, {double defaultValue = 0.0}) {
  if (v == null) return defaultValue;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  return double.tryParse(s) ?? defaultValue;
}

/// Parsea un valor numérico opcional a double, retornando null si es nulo o inválido.
double? _toNullableDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  return double.tryParse(s);
}

/// Parsea un valor numérico a int de forma segura, ya sea num, String o null.
int _toInt(dynamic v, {int defaultValue = 0}) {
  if (v == null) return defaultValue;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  return int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? defaultValue;
}

