import 'package:equatable/equatable.dart';

/// Estado de una cuenta por pagar — `AccountPayable.status` en
/// `docs/api/components.yaml` (PENDING/PARTIAL/PAID/OVERDUE).
enum AccountPayableStatus {
  pending,
  partial,
  paid,
  overdue;

  String get apiValue => switch (this) {
        AccountPayableStatus.pending => 'PENDING',
        AccountPayableStatus.partial => 'PARTIAL',
        AccountPayableStatus.paid => 'PAID',
        AccountPayableStatus.overdue => 'OVERDUE',
      };

  String get label => switch (this) {
        AccountPayableStatus.pending => 'Pendiente',
        AccountPayableStatus.partial => 'Abonada',
        AccountPayableStatus.paid => 'Pagada',
        AccountPayableStatus.overdue => 'Vencida',
      };
}

/// Método de pago al liquidar una cuenta por pagar — `PaymentMethodType` de
/// `docs/api/components.yaml`, reutilizado aquí (no confundir con
/// `PaymentMethodMxn` de `sales_pos`, que es el cobro de mostrador).
enum SupplierPaymentMethod {
  cashMxn,
  spei,
  codi,
  cardTpv,
  mixed;

  String get apiValue => switch (this) {
        SupplierPaymentMethod.cashMxn => 'CASH_MXN',
        SupplierPaymentMethod.spei => 'SPEI',
        SupplierPaymentMethod.codi => 'CODI',
        SupplierPaymentMethod.cardTpv => 'CARD_TPV',
        SupplierPaymentMethod.mixed => 'MIXED',
      };

  String get label => switch (this) {
        SupplierPaymentMethod.cashMxn => 'Efectivo',
        SupplierPaymentMethod.spei => 'SPEI',
        SupplierPaymentMethod.codi => 'CoDi',
        SupplierPaymentMethod.cardTpv => 'Tarjeta (TPV)',
        SupplierPaymentMethod.mixed => 'Mixto',
      };
}

/// Semáforo de vencimiento — Subtarea 11.2.3 (Tablero de CxP con Semáforo).
enum PayableUrgency {
  /// Verde — a tiempo.
  onTime,

  /// Amarillo — vence en 3 días o menos.
  dueSoon,

  /// Rojo — vencida.
  overdue,
}

/// Cuenta por pagar a un proveedor — modelada sobre `AccountPayable` de
/// `docs/api/components.yaml`.
///
/// Trazabilidad: Constitución Art. I (1.2.8) · Doc. Maestro Sección 5.3
///              (RF-16) · HU-17 / CU-22
class AccountPayable extends Equatable {
  const AccountPayable({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseOrderId,
    required this.originalAmountMxn,
    required this.paidAmountMxn,
    required this.dueDate,
    required this.createdAt,
  });

  final String id;
  final String supplierId;
  final String supplierName;
  final String purchaseOrderId;
  final double originalAmountMxn;
  final double paidAmountMxn;
  final DateTime dueDate;
  final DateTime createdAt;

  double get balanceMxn => originalAmountMxn - paidAmountMxn;

  /// Estado calculado en el cliente a partir del saldo y la fecha de
  /// vencimiento — mismo criterio que `Product.stockStatus`: el backend es
  /// la fuente de verdad cuando exista (Tarea 11.1), el cliente solo
  /// clasifica mientras se opera contra el mock.
  AccountPayableStatus get status {
    if (balanceMxn <= 0.005) return AccountPayableStatus.paid;
    if (DateTime.now().isAfter(dueDate)) return AccountPayableStatus.overdue;
    if (paidAmountMxn > 0) return AccountPayableStatus.partial;
    return AccountPayableStatus.pending;
  }

  /// Semáforo visual de la tarjeta (11.2.3).
  PayableUrgency get urgency {
    final daysUntilDue = dueDate.difference(DateTime.now()).inDays;
    if (daysUntilDue < 0) return PayableUrgency.overdue;
    if (daysUntilDue <= 3) return PayableUrgency.dueSoon;
    return PayableUrgency.onTime;
  }

  AccountPayable copyWith({double? paidAmountMxn}) => AccountPayable(
        id: id,
        supplierId: supplierId,
        supplierName: supplierName,
        purchaseOrderId: purchaseOrderId,
        originalAmountMxn: originalAmountMxn,
        paidAmountMxn: paidAmountMxn ?? this.paidAmountMxn,
        dueDate: dueDate,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props => [
        id,
        supplierId,
        supplierName,
        purchaseOrderId,
        originalAmountMxn,
        paidAmountMxn,
        dueDate,
        createdAt,
      ];
}

/// Resumen agregado — espejo de `data.summary` en
/// `GET /accounts-payable` (`docs/api/purchases.yaml`).
class AccountsPayableSummary extends Equatable {
  const AccountsPayableSummary({
    required this.totalPendingMxn,
    required this.overdueAmountMxn,
    required this.overdueCount,
  });

  final double totalPendingMxn;
  final double overdueAmountMxn;
  final int overdueCount;

  @override
  List<Object?> get props => [totalPendingMxn, overdueAmountMxn, overdueCount];
}
