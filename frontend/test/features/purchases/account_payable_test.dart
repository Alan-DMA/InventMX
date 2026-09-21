import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/purchases/domain/account_payable.dart';

AccountPayable _makePayable({
  required DateTime dueDate,
  double originalAmountMxn = 1000,
  double paidAmountMxn = 0,
  AccountPayableStatus status = AccountPayableStatus.pending,
}) {
  final now = DateTime.now();
  return AccountPayable(
    id: 'ap-1',
    supplierId: 'sup-1',
    supplierName: 'Proveedor Test',
    purchaseOrderId: 'po-1',
    originalAmountMxn: originalAmountMxn,
    paidAmountMxn: paidAmountMxn,
    status: status,
    dueDate: dueDate,
    createdAt: now.subtract(const Duration(days: 10)),
    updatedAt: now.subtract(const Duration(days: 10)),
  );
}

void main() {
  group('AccountPayable — semáforo de vencimiento (11.2.3)', () {
    test('vencimiento a más de 3 días → onTime (verde)', () {
      final payable = _makePayable(dueDate: DateTime.now().add(const Duration(days: 10)));
      expect(payable.urgency, PayableUrgency.onTime);
    });

    test('vencimiento en 3 días o menos → dueSoon (amarillo)', () {
      final payable = _makePayable(dueDate: DateTime.now().add(const Duration(days: 2)));
      expect(payable.urgency, PayableUrgency.dueSoon);
    });

    test('fecha de vencimiento ya pasada → overdue (rojo)', () {
      final payable = _makePayable(dueDate: DateTime.now().subtract(const Duration(days: 1)));
      expect(payable.urgency, PayableUrgency.overdue);
    });

    test('status OVERDUE del backend manda aunque la fecha aún no venza', () {
      // El backend es la fuente de verdad del estado — el cliente ya no
      // deriva OVERDUE sólo de la fecha (Sep 2026, integración real).
      final payable = _makePayable(
        dueDate: DateTime.now().add(const Duration(days: 10)),
        status: AccountPayableStatus.overdue,
      );
      expect(payable.urgency, PayableUrgency.overdue);
    });
  });

  group('AccountPayable — saldo', () {
    test('balanceMxn resta lo abonado del monto original', () {
      final payable = _makePayable(
        dueDate: DateTime.now().add(const Duration(days: 10)),
        paidAmountMxn: 400,
      );
      expect(payable.balanceMxn, 600);
    });

    test('copyWith actualiza abono y estado sin tocar el resto', () {
      final payable = _makePayable(dueDate: DateTime.now().add(const Duration(days: 10)));
      final updated = payable.copyWith(
        paidAmountMxn: 1000,
        status: AccountPayableStatus.paid,
      );
      expect(updated.status, AccountPayableStatus.paid);
      expect(updated.balanceMxn, 0);
      expect(updated.id, payable.id);
      expect(updated.dueDate, payable.dueDate);
    });
  });
}
