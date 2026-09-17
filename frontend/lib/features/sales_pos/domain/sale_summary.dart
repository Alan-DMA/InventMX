import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'cart_state.dart';
import 'payment_entry.dart';

/// Cómo se pagó una venta, visto desde el renglón del kardex.
///
/// Es el `PaymentMethodType` de `docs/api/components.yaml`
/// (`CASH_MXN | SPEI | CODI | CARD_TPV | MIXED`): un método → ese método;
/// dos o más → `mixed`. Sirve tanto para pintar el renglón como para el
/// filtro `payment_method` de `GET /sales`.
enum SalePaymentKind {
  cash,
  card,
  spei,
  codi,
  other,
  mixed;

  static SalePaymentKind fromPayments(List<PaymentEntry> payments) {
    final methods = payments.map((p) => p.method).toSet();
    if (methods.isEmpty) return SalePaymentKind.other;
    if (methods.length > 1) return SalePaymentKind.mixed;
    return switch (methods.single) {
      PaymentMethodMxn.cashMxn => SalePaymentKind.cash,
      PaymentMethodMxn.cardTpv => SalePaymentKind.card,
      PaymentMethodMxn.spei => SalePaymentKind.spei,
      PaymentMethodMxn.codi => SalePaymentKind.codi,
      PaymentMethodMxn.other => SalePaymentKind.other,
    };
  }

  /// Valor del query param `payment_method` (docs/api/sales.yaml).
  String get apiValue => switch (this) {
        SalePaymentKind.cash => 'CASH_MXN',
        SalePaymentKind.card => 'CARD_TPV',
        SalePaymentKind.spei => 'SPEI',
        SalePaymentKind.codi => 'CODI',
        SalePaymentKind.other => 'OTHER',
        SalePaymentKind.mixed => 'MIXED',
      };

  String get label => switch (this) {
        SalePaymentKind.cash => 'Efectivo',
        SalePaymentKind.card => 'Tarjeta',
        SalePaymentKind.spei => 'SPEI',
        SalePaymentKind.codi => 'CoDi',
        SalePaymentKind.other => 'Otro',
        SalePaymentKind.mixed => 'Mixto',
      };

  IconData get icon => switch (this) {
        SalePaymentKind.cash => Icons.payments_outlined,
        SalePaymentKind.card => Icons.credit_card_rounded,
        SalePaymentKind.spei => Icons.account_balance_outlined,
        SalePaymentKind.codi => Icons.qr_code_2_rounded,
        SalePaymentKind.other => Icons.more_horiz_rounded,
        SalePaymentKind.mixed => Icons.call_split_rounded,
      };

  /// Un solo acento por familia: efectivo en esmeralda (es lo que cuadra la
  /// caja), lo bancario en skyBlue, mixto y otro en neutro.
  Color get color => switch (this) {
        SalePaymentKind.cash => AppColors.emerald,
        SalePaymentKind.card ||
        SalePaymentKind.spei ||
        SalePaymentKind.codi =>
          AppColors.skyBlue,
        SalePaymentKind.other ||
        SalePaymentKind.mixed =>
          AppColors.onSurfaceMuted,
      };
}

/// Renglón del kardex de ventas — la proyección de `Sale`
/// (`docs/api/components.yaml`) que necesita la lista, sin ítems ni pagos.
///
/// El detalle completo se pide aparte con `GET /sales/{id}`.
class SaleSummary extends Equatable {
  const SaleSummary({
    required this.id,
    required this.folio,
    required this.completedAt,
    required this.cashierName,
    required this.totalMxn,
    required this.itemCount,
    required this.paymentKind,
    required this.isRefunded,
  });

  factory SaleSummary.fromCheckout(CheckoutResult r) => SaleSummary(
        id: r.saleId,
        folio: r.folio,
        completedAt: r.completedAt,
        cashierName: r.cashierName,
        totalMxn: r.totalMxn,
        itemCount: r.items.fold<int>(0, (a, i) => a + i.quantity),
        paymentKind: SalePaymentKind.fromPayments(r.payments),
        isRefunded: r.isRefunded,
      );

  final String id;
  final String folio;
  final DateTime completedAt;
  final String cashierName;

  /// El total histórico de la venta — no se ajusta si luego se reembolsa.
  /// El renglón muestra este monto con la etiqueta "Reembolsada" al lado,
  /// no un monto descontado (es un kardex: registra el hecho, no lo oculta).
  final double totalMxn;

  /// Unidades vendidas (suma de cantidades), no líneas.
  final int itemCount;
  final SalePaymentKind paymentKind;
  final bool isRefunded;

  @override
  List<Object?> get props => [
        id,
        folio,
        completedAt,
        cashierName,
        totalMxn,
        itemCount,
        paymentKind,
        isRefunded,
      ];
}
