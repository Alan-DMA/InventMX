import 'package:equatable/equatable.dart';

/// Métodos de pago aceptados en el cobro mixto del POS.
///
/// Trazabilidad: Constitución Art. VII (7.2) · Doc. Maestro RF-14, SR-04 · HU-13 / CU-14
enum PaymentMethodMxn {
  cashMxn,
  spei,
  cardTpv,
  codi,
  other;

  /// Valor enviado a `POST /sales/checkout` (docs/api/sales.yaml).
  String get apiValue => switch (this) {
        PaymentMethodMxn.cashMxn => 'CASH_MXN',
        PaymentMethodMxn.spei => 'SPEI',
        PaymentMethodMxn.cardTpv => 'CARD_TPV',
        PaymentMethodMxn.codi => 'CODI',
        PaymentMethodMxn.other => 'OTHER',
      };

  String get label => switch (this) {
        PaymentMethodMxn.cashMxn => 'Efectivo',
        PaymentMethodMxn.spei => 'SPEI',
        PaymentMethodMxn.cardTpv => 'Tarjeta (TPV)',
        PaymentMethodMxn.codi => 'CoDi',
        PaymentMethodMxn.other => 'Otro',
      };

  /// El folio/referencia solo aplica a métodos distintos de Efectivo.
  bool get requiresReference => this != PaymentMethodMxn.cashMxn;
}

/// Un método de pago agregado al cobro de una venta (pago mixto).
///
/// Trazabilidad: Constitución Art. VII (7.2) · Doc. Maestro RF-14, SR-04 · HU-13 / CU-14
class PaymentEntry extends Equatable {
  const PaymentEntry({
    required this.id,
    required this.method,
    required this.amountMxn,
    this.referenceCode,
  });

  /// ID único local de la entrada (no viaja al backend).
  final String id;

  final PaymentMethodMxn method;

  final double amountMxn;

  /// Folio/referencia opcional — solo relevante si `method != cashMxn`.
  final String? referenceCode;

  @override
  List<Object?> get props => [id, method, amountMxn, referenceCode];
}
