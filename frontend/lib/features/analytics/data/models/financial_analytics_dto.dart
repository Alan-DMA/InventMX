// DTOs fuertemente tipados para Finanzas, Rentabilidad y Flujo de Caja (RF-18, RF-19 / Const. Art. 7.6)
// Cumplimiento estricto de .agents/AGENTS.md:
// 1. Moneda base en Pesos Mexicanos ($ MXN).
// 2. Prohibición de mapas crudos (Map<String, dynamic>) en capas de UI/Negocio.
// 3. Serialización y deserialización a prueba de nulos.
// 4. Comentarios exhaustivos línea por línea.

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
  factory PaymentMethodMetricDto.fromJson(Map<String, dynamic> json) {
    return PaymentMethodMetricDto(
      paymentMethod: json['payment_method'] as String? ?? 'OTHER',
      totalMxn: (json['total_mxn'] as num?)?.toDouble() ?? 0.0,
      transactionCount: json['transaction_count'] as int? ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Serialización segura a JSON.
  Map<String, dynamic> toJson() {
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
    required this.cogsMxn,
    required this.grossProfitMxn,
    required this.profitMarginPct,
    required this.averageTicketMxn,
    required this.totalTransactions,
    required this.paymentMethods,
  });

  /// Deserialización segura desde JSON.
  factory ExecutiveFinancialSummaryDto.fromJson(Map<String, dynamic> json) {
    return ExecutiveFinancialSummaryDto(
      periodStart: json['period_start'] != null
          ? DateTime.tryParse(json['period_start'] as String) ?? DateTime.now()
          : DateTime.now(),
      periodEnd: json['period_end'] != null
          ? DateTime.tryParse(json['period_end'] as String) ?? DateTime.now()
          : DateTime.now(),
      grossSalesMxn: (json['gross_sales_mxn'] as num?)?.toDouble() ?? 0.0,
      discountsMxn: (json['discounts_mxn'] as num?)?.toDouble() ?? 0.0,
      netSalesMxn: (json['net_sales_mxn'] as num?)?.toDouble() ?? 0.0,
      cogsMxn: (json['cogs_mxn'] as num?)?.toDouble() ?? 0.0,
      grossProfitMxn: (json['gross_profit_mxn'] as num?)?.toDouble() ?? 0.0,
      profitMarginPct: (json['profit_margin_pct'] as num?)?.toDouble() ?? 0.0,
      averageTicketMxn: (json['average_ticket_mxn'] as num?)?.toDouble() ?? 0.0,
      totalTransactions: json['total_transactions'] as int? ?? 0,
      paymentMethods: (json['payment_methods'] as List<dynamic>?)
              ?.map((e) => PaymentMethodMetricDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Serialización segura a JSON.
  Map<String, dynamic> toJson() {
    return {
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'gross_sales_mxn': grossSalesMxn,
      'discounts_mxn': discountsMxn,
      'net_sales_mxn': netSalesMxn,
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
  factory CashFlowSummaryDto.fromJson(Map<String, dynamic> json) {
    return CashFlowSummaryDto(
      periodStart: json['period_start'] != null
          ? DateTime.tryParse(json['period_start'] as String) ?? DateTime.now()
          : DateTime.now(),
      periodEnd: json['period_end'] != null
          ? DateTime.tryParse(json['period_end'] as String) ?? DateTime.now()
          : DateTime.now(),
      cashSalesInflowMxn: (json['cash_sales_inflow_mxn'] as num?)?.toDouble() ?? 0.0,
      creditCollectionsInflowMxn: (json['credit_collections_inflow_mxn'] as num?)?.toDouble() ?? 0.0,
      cashIncomeMovementsMxn: (json['cash_income_movements_mxn'] as num?)?.toDouble() ?? 0.0,
      totalInflowMxn: (json['total_inflow_mxn'] as num?)?.toDouble() ?? 0.0,
      supplierPaymentsOutflowMxn: (json['supplier_payments_outflow_mxn'] as num?)?.toDouble() ?? 0.0,
      cashExpenseMovementsMxn: (json['cash_expense_movements_mxn'] as num?)?.toDouble() ?? 0.0,
      totalOutflowMxn: (json['total_outflow_mxn'] as num?)?.toDouble() ?? 0.0,
      netCashFlowMxn: (json['net_cash_flow_mxn'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Serialización segura a JSON.
  Map<String, dynamic> toJson() {
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
