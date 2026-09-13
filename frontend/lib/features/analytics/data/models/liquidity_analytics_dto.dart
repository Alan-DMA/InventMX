// DTOs fuertemente tipados para Capital de Trabajo y Posición de Liquidez (RF-21 / Const. Art. 7.6)
// Cumplimiento estricto de .agents/AGENTS.md:
// 1. Moneda base en Pesos Mexicanos ($ MXN).
// 2. Prohibición de mapas crudos (Map<String, dynamic>) en capas de UI/Negocio.
// 3. Serialización y deserialización a prueba de nulos.
// 4. Comentarios exhaustivos línea por línea.

/// DTO de respuesta para el Capital de Trabajo y Posición Neta de Liquidez (RF-21).
class WorkingCapitalDto {
  /// Fecha y hora del cálculo de liquidez.
  final DateTime asOfDate;
  /// Dinero en efectivo disponible en cajas activas en Pesos Mexicanos ($ MXN).
  final double cashInRegisterMxn;
  /// Cuentas por cobrar a clientes (cartera de crédito activo) en $ MXN.
  final double accountsReceivableMxn;
  /// Cuentas por pagar a proveedores pendientes en $ MXN.
  final double accountsPayableMxn;
  /// Capital de trabajo neto operativo en $ MXN (Caja + Por Cobrar - Por Pagar).
  final double netWorkingCapitalMxn;

  /// Constructor inmutable de capital de trabajo.
  const WorkingCapitalDto({
    required this.asOfDate,
    required this.cashInRegisterMxn,
    required this.accountsReceivableMxn,
    required this.accountsPayableMxn,
    required this.netWorkingCapitalMxn,
  });

  /// Deserialización segura desde JSON.
  factory WorkingCapitalDto.fromJson(Map<String, dynamic> json) {
    return WorkingCapitalDto(
      asOfDate: json['as_of_date'] != null
          ? DateTime.tryParse(json['as_of_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      cashInRegisterMxn: (json['cash_in_register_mxn'] as num?)?.toDouble() ?? 0.0,
      accountsReceivableMxn: (json['accounts_receivable_mxn'] as num?)?.toDouble() ?? 0.0,
      accountsPayableMxn: (json['accounts_payable_mxn'] as num?)?.toDouble() ?? 0.0,
      netWorkingCapitalMxn: (json['net_working_capital_mxn'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Serialización segura a JSON.
  Map<String, dynamic> toJson() {
    return {
      'as_of_date': asOfDate.toIso8601String(),
      'cash_in_register_mxn': cashInRegisterMxn,
      'accounts_receivable_mxn': accountsReceivableMxn,
      'accounts_payable_mxn': accountsPayableMxn,
      'net_working_capital_mxn': netWorkingCapitalMxn,
    };
  }
}
