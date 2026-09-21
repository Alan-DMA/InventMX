import 'package:equatable/equatable.dart';

/// Estado de una cuenta por pagar — `AccountPayableStatus` real del backend
/// (`backend/app/modules/purchasing_suppliers/domain/account_payable.py`).
/// El backend es la fuente de verdad (`status`/`is_overdue` ya calculados
/// server-side) — el cliente ya no deriva el estado a partir del saldo.
enum AccountPayableStatus {
  pending,
  partiallyPaid,
  paid,
  overdue,
  cancelled;

  String get apiValue => switch (this) {
        AccountPayableStatus.pending => 'PENDING',
        AccountPayableStatus.partiallyPaid => 'PARTIALLY_PAID',
        AccountPayableStatus.paid => 'PAID',
        AccountPayableStatus.overdue => 'OVERDUE',
        AccountPayableStatus.cancelled => 'CANCELLED',
      };

  static AccountPayableStatus fromApi(String value) => switch (value) {
        'PARTIALLY_PAID' => AccountPayableStatus.partiallyPaid,
        'PAID' => AccountPayableStatus.paid,
        'OVERDUE' => AccountPayableStatus.overdue,
        'CANCELLED' => AccountPayableStatus.cancelled,
        _ => AccountPayableStatus.pending,
      };

  String get label => switch (this) {
        AccountPayableStatus.pending => 'Pendiente',
        AccountPayableStatus.partiallyPaid => 'Abonada',
        AccountPayableStatus.paid => 'Pagada',
        AccountPayableStatus.overdue => 'Vencida',
        AccountPayableStatus.cancelled => 'Cancelada',
      };
}

/// Método de pago al liquidar una cuenta por pagar — `PaymentMethod` real del
/// backend (reutilizado de `sales_pos`, no confundir con `PaymentMethodMxn`
/// del cobro de mostrador).
///
/// Sin "Mixto" (decisión de Eduardo, Sep 2026): el backend sólo acepta un
/// método por abono — un pago combinado se registra como dos abonos
/// separados, que el backend ya soporta.
enum SupplierPaymentMethod {
  cashMxn,
  spei,
  codi,
  cardTpv,
  other;

  String get apiValue => switch (this) {
        SupplierPaymentMethod.cashMxn => 'CASH_MXN',
        SupplierPaymentMethod.spei => 'SPEI',
        SupplierPaymentMethod.codi => 'CODI',
        SupplierPaymentMethod.cardTpv => 'CARD_TPV',
        SupplierPaymentMethod.other => 'OTHER',
      };

  String get label => switch (this) {
        SupplierPaymentMethod.cashMxn => 'Efectivo',
        SupplierPaymentMethod.spei => 'SPEI',
        SupplierPaymentMethod.codi => 'CoDi',
        SupplierPaymentMethod.cardTpv => 'Tarjeta (TPV)',
        SupplierPaymentMethod.other => 'Otro',
      };
}

/// Semáforo de vencimiento — Subtarea 11.2.3 (Tablero de CxP con Semáforo).
/// Visual únicamente, derivado de `dueDate`/`status` — no viaja al backend.
enum PayableUrgency {
  /// Verde — a tiempo.
  onTime,

  /// Amarillo — vence en 3 días o menos.
  dueSoon,

  /// Rojo — vencida.
  overdue,
}

/// Cuenta por pagar a un proveedor — modelada sobre `AccountPayableResponse`
/// del backend real (`schemas/account_payable.py`).
///
/// Trazabilidad: Constitución Art. I (1.2.8) · Doc. Maestro Sección 5.3
///              (RF-16) · HU-17 / CU-22
class AccountPayable extends Equatable {
  const AccountPayable({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.originalAmountMxn,
    required this.paidAmountMxn,
    required this.status,
    required this.dueDate,
    required this.createdAt,
    required this.updatedAt,
    this.purchaseOrderId,
    this.folio,
    this.invoiceReference,
    this.notes,
  });

  final String id;
  final String supplierId;
  final String supplierName;
  final String? purchaseOrderId;
  final String? folio;
  final double originalAmountMxn;
  final double paidAmountMxn;
  final AccountPayableStatus status;
  final String? invoiceReference;
  final String? notes;
  final DateTime dueDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get balanceMxn => originalAmountMxn - paidAmountMxn;

  /// Semáforo visual de la tarjeta (11.2.3) — el estado real viene del
  /// backend en [status]; esto sólo clasifica la urgencia visual.
  PayableUrgency get urgency {
    if (status == AccountPayableStatus.overdue) return PayableUrgency.overdue;
    final daysUntilDue = dueDate.difference(DateTime.now()).inDays;
    if (daysUntilDue < 0) return PayableUrgency.overdue;
    if (daysUntilDue <= 3) return PayableUrgency.dueSoon;
    return PayableUrgency.onTime;
  }

  AccountPayable copyWith({
    double? paidAmountMxn,
    AccountPayableStatus? status,
  }) =>
      AccountPayable(
        id: id,
        supplierId: supplierId,
        supplierName: supplierName,
        purchaseOrderId: purchaseOrderId,
        folio: folio,
        originalAmountMxn: originalAmountMxn,
        paidAmountMxn: paidAmountMxn ?? this.paidAmountMxn,
        status: status ?? this.status,
        invoiceReference: invoiceReference,
        notes: notes,
        dueDate: dueDate,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  @override
  List<Object?> get props => [
        id,
        supplierId,
        supplierName,
        purchaseOrderId,
        folio,
        originalAmountMxn,
        paidAmountMxn,
        status,
        invoiceReference,
        notes,
        dueDate,
        createdAt,
        updatedAt,
      ];
}

/// Resumen agregado — espejo de `AccountsPayableSummaryResponse` real
/// (`GET /accounts-payable/summary`).
class AccountsPayableSummary extends Equatable {
  const AccountsPayableSummary({
    required this.totalPendingMxn,
    required this.totalPaidMxn,
    required this.overdueAmountMxn,
    required this.overdueCount,
    required this.pendingCount,
  });

  final double totalPendingMxn;
  final double totalPaidMxn;
  final double overdueAmountMxn;
  final int overdueCount;
  final int pendingCount;

  @override
  List<Object?> get props => [
        totalPendingMxn,
        totalPaidMxn,
        overdueAmountMxn,
        overdueCount,
        pendingCount,
      ];
}
