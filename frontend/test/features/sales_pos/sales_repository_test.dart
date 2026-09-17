import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_state.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';
import 'package:nexus_app/features/sales_pos/domain/sale_summary.dart';

// ---------------------------------------------------------------------------
// Fase 2 — Kardex de ventas: contrato de `GET /sales` sobre el mock
// ---------------------------------------------------------------------------

final _now = DateTime(2026, 9, 17, 15, 30);

void main() {
  late SalesRepositoryMock repo;

  setUp(() => repo = SalesRepositoryMock(clock: () => _now));

  group('SalePaymentKind', () {
    test('un método → ese método; dos → mixto', () {
      const cash = PaymentEntry(id: 'a', method: PaymentMethodMxn.cashMxn, amountMxn: 50);
      const card = PaymentEntry(id: 'b', method: PaymentMethodMxn.cardTpv, amountMxn: 50);
      expect(SalePaymentKind.fromPayments([cash]), SalePaymentKind.cash);
      expect(SalePaymentKind.fromPayments([card]), SalePaymentKind.card);
      expect(SalePaymentKind.fromPayments([cash, card]), SalePaymentKind.mixed);
      expect(SalePaymentKind.fromPayments([]), SalePaymentKind.other);
    });
  });

  group('getSales', () {
    test('la semilla cubre 7 días relativos al reloj, de más reciente a más antigua', () async {
      final page = await repo.getSales(pageSize: 100);
      expect(page.items, isNotEmpty);
      for (var i = 1; i < page.items.length; i++) {
        expect(
          page.items[i - 1].completedAt.isAfter(page.items[i].completedAt) ||
              page.items[i - 1].completedAt == page.items[i].completedAt,
          isTrue,
        );
      }
      // Nada en el futuro ni más viejo que una semana.
      expect(page.items.first.completedAt.isBefore(_now), isTrue);
      expect(
        page.items.last.completedAt.isAfter(_now.subtract(const Duration(days: 7))),
        isTrue,
      );
    });

    test('pagina de 20 en 20 y el total es del recorte, no de la página', () async {
      final p1 = await repo.getSales(page: 1, pageSize: 20);
      final p2 = await repo.getSales(page: 2, pageSize: 20);
      expect(p1.items.length, 20);
      expect(p1.total, greaterThan(20));
      expect(p1.totalPages, (p1.total / 20).ceil());
      expect(p2.items, isNotEmpty);
      expect(p2.items.first.id, isNot(p1.items.first.id));
      // Los agregados no cambian con la página.
      expect(p2.total, p1.total);
      expect(p2.totalAmountMxn, p1.totalAmountMxn);
    });

    test('filtra por forma de pago y la suma corresponde al recorte', () async {
      final all = await repo.getSales(pageSize: 100);
      final cash = await repo.getSales(
        query: const SalesQuery(paymentKind: SalePaymentKind.cash),
        pageSize: 100,
      );
      expect(cash.items.every((s) => s.paymentKind == SalePaymentKind.cash), isTrue);
      expect(cash.total, lessThan(all.total));
      final expectedSum = cash.items.fold<double>(0, (a, s) => a + s.totalMxn);
      expect(cash.totalAmountMxn, closeTo(expectedSum, 0.001));
    });

    test('filtra por cajero y por rango de fechas (inclusivo por día)', () async {
      final cashiers = await repo.getCashiers();
      expect(cashiers, contains('María Hernández'));

      final byCashier = await repo.getSales(
        query: const SalesQuery(cashierName: 'María Hernández'),
        pageSize: 100,
      );
      expect(byCashier.items.every((s) => s.cashierName == 'María Hernández'), isTrue);

      final today = DateTime(_now.year, _now.month, _now.day);
      final onlyToday = await repo.getSales(
        query: SalesQuery(dateFrom: today, dateTo: today),
        pageSize: 100,
      );
      expect(onlyToday.items, isNotEmpty);
      expect(
        onlyToday.items.every((s) =>
            s.completedAt.year == today.year &&
            s.completedAt.month == today.month &&
            s.completedAt.day == today.day),
        isTrue,
      );
    });

    test('una venta cobrada en la sesión aparece primero y se resuelve por id', () async {
      final result = await repo.checkout(
        items: const [
          CartItem(id: 'c1', name: 'Coca-Cola 600 ml', unitPriceMxn: 18, quantity: 2),
        ],
        payments: const [
          PaymentEntry(id: 'p1', method: PaymentMethodMxn.cashMxn, amountMxn: 50),
        ],
        cashierName: 'Eduardo',
      );

      final page = await repo.getSales();
      expect(page.items.first.id, result.saleId);
      expect(page.items.first.itemCount, 2);
      expect(page.items.first.paymentKind, SalePaymentKind.cash);

      final detail = await repo.getSaleById(result.saleId);
      expect(detail.folio, result.folio);
      expect(detail.items.single.name, 'Coca-Cola 600 ml');
    });

    test('id desconocido lanza SaleNotFoundException', () {
      expect(
        () => repo.getSaleById('no-existe'),
        throwsA(isA<SaleNotFoundException>()),
      );
    });
  });

  group('refundSale', () {
    Future<CheckoutResult> checkoutTwoLines() => repo.checkout(
          items: const [
            CartItem(id: 'ci-1', name: 'Coca-Cola 600 ml', unitPriceMxn: 18, quantity: 3),
            CartItem(id: 'ci-2', name: 'Sabritas 45 g', unitPriceMxn: 17, quantity: 2),
          ],
          payments: const [
            PaymentEntry(id: 'p1', method: PaymentMethodMxn.cashMxn, amountMxn: 100),
          ],
          cashierName: 'Eduardo',
        );

    test('reembolso total: sin itemsToRefund cubre todos los ítems', () async {
      final sale = await checkoutTwoLines();
      final updated = await repo.refundSale(
        saleId: sale.saleId,
        reason: 'Cliente se arrepintió',
        refundToStock: true,
      );

      expect(updated.isRefunded, isTrue);
      expect(updated.refund!.refundAmountMxn, closeTo(sale.totalMxn, 0.001));
      expect(updated.netTotalMxn, closeTo(0, 0.001));
      expect(updated.refund!.lines, hasLength(2));

      // El detalle y el listado ven la misma venta actualizada.
      final detail = await repo.getSaleById(sale.saleId);
      expect(detail.isRefunded, isTrue);
    });

    test('reembolso parcial: sólo se descuenta lo seleccionado', () async {
      final sale = await checkoutTwoLines();
      final updated = await repo.refundSale(
        saleId: sale.saleId,
        reason: 'Sólo un producto venía defectuoso',
        refundToStock: false,
        itemsToRefund: const [RefundedLine(cartItemId: 'ci-2', quantity: 1)],
      );

      expect(updated.refund!.refundAmountMxn, closeTo(17, 0.001));
      expect(updated.netTotalMxn, closeTo(sale.totalMxn - 17, 0.001));
      expect(updated.refund!.refundToStock, isFalse);
    });

    test('no se puede reembolsar dos veces', () async {
      final sale = await checkoutTwoLines();
      await repo.refundSale(saleId: sale.saleId, reason: 'x', refundToStock: true);

      expect(
        () => repo.refundSale(saleId: sale.saleId, reason: 'y', refundToStock: true),
        throwsA(isA<SaleAlreadyRefundedException>()),
      );
    });

    test('no se puede reembolsar más de lo vendido', () async {
      final sale = await checkoutTwoLines();
      expect(
        () => repo.refundSale(
          saleId: sale.saleId,
          reason: 'x',
          refundToStock: true,
          itemsToRefund: const [RefundedLine(cartItemId: 'ci-1', quantity: 10)],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('venta desconocida lanza SaleNotFoundException', () {
      expect(
        () => repo.refundSale(saleId: 'no-existe', reason: 'x', refundToStock: true),
        throwsA(isA<SaleNotFoundException>()),
      );
    });

    test('el listado refleja el neto tras un reembolso parcial', () async {
      final before = await repo.getSales(pageSize: 200);
      final sale = await checkoutTwoLines();
      await repo.refundSale(
        saleId: sale.saleId,
        reason: 'x',
        refundToStock: true,
        itemsToRefund: const [RefundedLine(cartItemId: 'ci-2', quantity: 1)],
      );

      final after = await repo.getSales(pageSize: 200);
      // Bruto subiría el total de la venta completa; neto sólo lo no
      // reembolsado — el listado debe reflejar lo segundo.
      final expectedNet = before.totalAmountMxn + (sale.totalMxn - 17);
      expect(after.totalAmountMxn, closeTo(expectedNet, 0.001));

      final row = after.items.firstWhere((s) => s.id == sale.saleId);
      expect(row.isRefunded, isTrue);
      // El renglón sigue mostrando el total histórico, no el neto.
      expect(row.totalMxn, closeTo(sale.totalMxn, 0.001));
    });
  });
}
