// DTOs fuertemente tipados para Finanzas, Rentabilidad y Flujo de Caja (RF-18, RF-19 / Const. Art. 7.6)
// Cumplimiento estricto de .agents/AGENTS.md:
// 1. Moneda base en Pesos Mexicanos ($ MXN).
// 2. Prohibición de mapas crudos (Map<String, dynamic>) en capas de UI/Negocio.
// 3. Serialización y deserialización a prueba de nulos.
// 4. Comentarios exhaustivos línea por línea.

import 'json_number.dart';

/// Presets temporales para filtrado de reportes analíticos.
enum DateRangePreset {
  today('TODAY'),
  thisWeek('THIS_WEEK'),
  thisMonth('THIS_MONTH'),
  lastMonth('LAST_MONTH'),
  custom('CUSTOM');

  final String value;
  const DateRangePreset(this.value);

  static DateRangePreset fromString(String val) {
    return DateRangePreset.values.firstWhere(
      (e) => e.value.toUpperCase() == val.toUpperCase(),
      orElse: () => DateRangePreset.thisMonth,
    );
  }
}

/// Métrica desglosada por método de pago.
class PaymentMethodMetricDto {
  /// Nombre del método contable de pago (ej: CASH_MXN, CARD_TPV, SPEI).
  final String paymentMethod;
  /// Importe total cobrado en Pesos Mexicanos ($ MXN).
  final double totalMxn;
  /// Cantidad total de transacciones registradas con este método.
  final int transactionCount;
  /// Porcentaje representativo respecto al total de ventas.
  final double percentage;

  /// Constructor inmutable de métrica de método de pago.
  const PaymentMethodMetricDto({
    required this.paymentMethod,
    required this.totalMxn,
    required this.transactionCount,
    required this.percentage,
  });

  /// Deserialización segura desde JSON.
  factory PaymentMethodMetricDto.fromJson(Map<dynamic, dynamic> json) {
    return PaymentMethodMetricDto(
      paymentMethod: json['payment_method'] as String? ?? 'OTHER',
      totalMxn: toDoubleOrZero(json['total_mxn']),
      transactionCount: toIntOrZero(json['transaction_count']),
      percentage: toDoubleOrZero(json['percentage']),
    );
  }

  /// Serialización segura a JSON.
  Map<dynamic, dynamic> toJson() {
    return {
      'payment_method': paymentMethod,
      'total_mxn': totalMxn,
      'transaction_count': transactionCount,
      'percentage': percentage,
    };
  }
}

/// DTO de respuesta para el Resumen Financiero Ejecutivo (RF-18).
class ExecutiveFinancialSummaryDto {
  /// Fecha de inicio del periodo analizado.
  final DateTime periodStart;
  /// Fecha de fin del periodo analizado.
  final DateTime periodEnd;
  /// Ventas brutas totales en Pesos Mexicanos ($ MXN).
  final double grossSalesMxn;
  /// Descuentos comerciales otorgados en $ MXN.
  final double discountsMxn;
  /// Ventas netas totales facturadas en $ MXN.
  final double netSalesMxn;
  /// Reembolsos del periodo en $ MXN (ya restados de las ventas netas).
  final double refundsMxn;
  /// Costo de Mercancía Vendida (COGS) en $ MXN basado en costo histórico.
  final double cogsMxn;
  /// Utilidad bruta en $ MXN (Ventas Netas - COGS).
  final double grossProfitMxn;
  /// Margen de utilidad bruta en porcentaje (Gross Profit / Net Sales * 100).
  final double profitMarginPct;
  /// Importe promedio de ticket por venta en $ MXN.
  final double averageTicketMxn;
  /// Cantidad total de ventas cerradas en el periodo.
  final int totalTransactions;
  /// Desglose por método de pago.
  final List<PaymentMethodMetricDto> paymentMethods;

  /// Constructor inmutable de resumen financiero ejecutivo.
  const ExecutiveFinancialSummaryDto({
    required this.periodStart,
    required this.periodEnd,
    required this.grossSalesMxn,
    required this.discountsMxn,
    required this.netSalesMxn,
    this.refundsMxn = 0.0,
    required this.cogsMxn,
    required this.grossProfitMxn,
    required this.profitMarginPct,
    required this.averageTicketMxn,
    required this.totalTransactions,
    required this.paymentMethods,
  });

  /// Deserialización segura desde JSON.
  factory ExecutiveFinancialSummaryDto.fromJson(Map<dynamic, dynamic> json) {
    return ExecutiveFinancialSummaryDto(
      periodStart: json['period_start'] != null
          ? DateTime.tryParse(json['period_start'] as String) ?? DateTime.now()
          : DateTime.now(),
      periodEnd: json['period_end'] != null
          ? DateTime.tryParse(json['period_end'] as String) ?? DateTime.now()
          : DateTime.now(),
      grossSalesMxn: toDoubleOrZero(json['gross_sales_mxn']),
      discountsMxn: toDoubleOrZero(json['discounts_mxn']),
      netSalesMxn: toDoubleOrZero(json['net_sales_mxn']),
      refundsMxn: toDoubleOrZero(json['refunds_mxn']),
      cogsMxn: toDoubleOrZero(json['cogs_mxn']),
      grossProfitMxn: toDoubleOrZero(json['gross_profit_mxn']),
      profitMarginPct: toDoubleOrZero(json['profit_margin_pct']),
      averageTicketMxn: toDoubleOrZero(json['average_ticket_mxn']),
      totalTransactions: toIntOrZero(json['total_transactions']),
      paymentMethods: (json['payment_methods'] as List<dynamic>?)
              ?.map((e) => PaymentMethodMetricDto.fromJson(e as Map<dynamic, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Serialización segura a JSON.
  Map<dynamic, dynamic> toJson() {
    return {
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'gross_sales_mxn': grossSalesMxn,
      'discounts_mxn': discountsMxn,
      'net_sales_mxn': netSalesMxn,
      'refunds_mxn': refundsMxn,
      'cogs_mxn': cogsMxn,
      'gross_profit_mxn': grossProfitMxn,
      'profit_margin_pct': profitMarginPct,
      'average_ticket_mxn': averageTicketMxn,
      'total_transactions': totalTransactions,
      'payment_methods': paymentMethods.map((m) => m.toJson()).toList(),
    };
  }
}

/// DTO de respuesta para el Resumen de Flujo de Caja y Tesorería Real (RF-19).
class CashFlowSummaryDto {
  /// Fecha inicial del periodo.
  final DateTime periodStart;
  /// Fecha final del periodo.
  final DateTime periodEnd;
  /// Entradas por ventas de contado en efectivo en $ MXN.
  final double cashSalesInflowMxn;
  /// Entradas por cobranza de créditos a clientes en $ MXN.
  final double creditCollectionsInflowMxn;
  /// Otras entradas manuales registradas en caja en $ MXN.
  final double cashIncomeMovementsMxn;
  /// Total general de entradas de efectivo en $ MXN.
  final double totalInflowMxn;
  /// Salidas por pagos realizados a proveedores en $ MXN.
  final double supplierPaymentsOutflowMxn;
  /// Salidas por gastos operativos y retiros de caja en $ MXN.
  final double cashExpenseMovementsMxn;
  /// Total general de salidas de efectivo en $ MXN.
  final double totalOutflowMxn;
  /// Flujo neto de efectivo en $ MXN (Entradas - Salidas).
  final double netCashFlowMxn;

  /// Constructor inmutable de flujo de caja.
  const CashFlowSummaryDto({
    required this.periodStart,
    required this.periodEnd,
    required this.cashSalesInflowMxn,
    required this.creditCollectionsInflowMxn,
    required this.cashIncomeMovementsMxn,
    required this.totalInflowMxn,
    required this.supplierPaymentsOutflowMxn,
    required this.cashExpenseMovementsMxn,
    required this.totalOutflowMxn,
    required this.netCashFlowMxn,
  });

  /// Deserialización segura desde JSON.
  factory CashFlowSummaryDto.fromJson(Map<dynamic, dynamic> json) {
    return CashFlowSummaryDto(
      periodStart: json['period_start'] != null
          ? DateTime.tryParse(json['period_start'] as String) ?? DateTime.now()
          : DateTime.now(),
      periodEnd: json['period_end'] != null
          ? DateTime.tryParse(json['period_end'] as String) ?? DateTime.now()
          : DateTime.now(),
      cashSalesInflowMxn: toDoubleOrZero(json['cash_sales_inflow_mxn']),
      creditCollectionsInflowMxn: toDoubleOrZero(json['credit_collections_inflow_mxn']),
      cashIncomeMovementsMxn: toDoubleOrZero(json['cash_income_movements_mxn']),
      totalInflowMxn: toDoubleOrZero(json['total_inflow_mxn']),
      supplierPaymentsOutflowMxn: toDoubleOrZero(json['supplier_payments_outflow_mxn']),
      cashExpenseMovementsMxn: toDoubleOrZero(json['cash_expense_movements_mxn']),
      totalOutflowMxn: toDoubleOrZero(json['total_outflow_mxn']),
      netCashFlowMxn: toDoubleOrZero(json['net_cash_flow_mxn']),
    );
  }

  /// Serialización segura a JSON.
  Map<dynamic, dynamic> toJson() {
    return {
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'cash_sales_inflow_mxn': cashSalesInflowMxn,
      'credit_collections_inflow_mxn': creditCollectionsInflowMxn,
      'cash_income_movements_mxn': cashIncomeMovementsMxn,
      'total_inflow_mxn': totalInflowMxn,
      'supplier_payments_outflow_mxn': supplierPaymentsOutflowMxn,
      'cash_expense_movements_mxn': cashExpenseMovementsMxn,
      'total_outflow_mxn': totalOutflowMxn,
      'net_cash_flow_mxn': netCashFlowMxn,
    };
  }
}

/// Un día natural de la serie de ventas (`GET /analytics/sales-trends`).
class DailySalesPointDto {
  /// Día natural (YYYY-MM-DD).
  final DateTime period;
  /// Ingreso neto del día en $ MXN (ventas − reembolsos).
  final double revenueMxn;
  /// Tickets cobrados en el día.
  final int ordersCount;
  /// Utilidad bruta del día en $ MXN.
  final double grossProfitMxn;

  /// Constructor inmutable de punto diario.
  const DailySalesPointDto({
    required this.period,
    required this.revenueMxn,
    required this.ordersCount,
    required this.grossProfitMxn,
  });

  /// Deserialización segura desde JSON.
  factory DailySalesPointDto.fromJson(Map<dynamic, dynamic> json) {
    return DailySalesPointDto(
      period: toDateTimeOrNull(json['period']) ?? DateTime.now(),
      revenueMxn: toDoubleOrZero(json['revenue_mxn']),
      ordersCount: toIntOrZero(json['orders_count']),
      grossProfitMxn: toDoubleOrZero(json['gross_profit_mxn']),
    );
  }
}

/// DTO de respuesta para la Serie Diaria de Ventas (RF-21).
class SalesTrendsDto {
  /// Fecha inicial del periodo.
  final DateTime periodStart;
  /// Fecha final del periodo.
  final DateTime periodEnd;
  /// Un punto por día natural; los días sin venta vienen en cero.
  final List<DailySalesPointDto> trends;

  /// Constructor inmutable de serie diaria.
  const SalesTrendsDto({
    required this.periodStart,
    required this.periodEnd,
    required this.trends,
  });

  /// Deserialización segura desde JSON.
  factory SalesTrendsDto.fromJson(Map<dynamic, dynamic> json) {
    return SalesTrendsDto(
      periodStart: toDateTimeOrNull(json['period_start']) ?? DateTime.now(),
      periodEnd: toDateTimeOrNull(json['period_end']) ?? DateTime.now(),
      trends: (json['trends'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(DailySalesPointDto.fromJson)
              .toList() ??
          const [],
    );
  }
}
