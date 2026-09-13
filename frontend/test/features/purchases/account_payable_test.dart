import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/purchases/domain/account_payable.dart';

AccountPayable _makePayable({
  required DateTime dueDate,
  double originalAmountMxn = 1000,
  double paidAmountMxn = 0,
}) {
  return AccountPayable(
    id: 'ap-1',
    supplierId: 'sup-1',
    supplierName: 'Proveedor Test',
    purchaseOrderId: 'po-1',
    originalAmountMxn: originalAmountMxn,
    paidAmountMxn: paidAmountMxn,
    dueDate: dueDate,
    createdAt: DateTime.now().subtract(const Duration(days: 10)),
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
  });

  group('AccountPayable — status calculado', () {
    test('sin abonos y a tiempo → pending', () {
      final payable = _makePayable(dueDate: DateTime.now().add(const Duration(days: 10)));
      expect(payable.status, AccountPayableStatus.pending);
    });

    test('con abono parcial y a tiempo → partial', () {
      final payable = _makePayable(
        dueDate: DateTime.now().add(const Duration(days: 10)),
        paidAmountMxn: 400,
      );
      expect(payable.status, AccountPayableStatus.partial);
      expect(payable.balanceMxn, 600);
    });

    test('saldo liquidado por completo → paid, sin importar la fecha', () {
      final payable = _makePayable(
        dueDate: DateTime.now().subtract(const Duration(days: 5)),
        paidAmountMxn: 1000,
      );
      expect(payable.status, AccountPayableStatus.paid);
    });

    test('vencida (con o sin abono parcial) → overdue', () {
      final payable = _makePayable(
        dueDate: DateTime.now().subtract(const Duration(days: 5)),
        paidAmountMxn: 300,
      );
      expect(payable.status, AccountPayableStatus.overdue);
      expect(payable.balanceMxn, 700);
    });
  });
}
