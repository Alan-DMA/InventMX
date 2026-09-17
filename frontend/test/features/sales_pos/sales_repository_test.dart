import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_state.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';
import 'package:nexus_app/features/sales_pos/domain/sale_summary.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockDioClient extends Mock implements DioClient {}

// ---------------------------------------------------------------------------
// Fase 2 — Kardex de ventas: contrato de `GET /sales` sobre el mock
// ---------------------------------------------------------------------------

final _now = DateTime(2026, 9, 17, 15, 30);

void main() {
  late SalesRepositoryMock repo;
  late MockDioClient mockClient;
  late SalesRepositoryImpl repository;

  setUp(() {
    repo = SalesRepositoryMock(clock: () => _now);
    mockClient = MockDioClient();
    repository = SalesRepositoryImpl(client: mockClient);
  });

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

  group('SalesRepositoryImpl — checkout()', () {
    final testItems = [
      const CartItem(
        id: 'cart-1',
        productId: 'a1111111-b222-c333-d444-e55555555555',
        name: 'Coca Cola 600ml',
        unitPriceMxn: 18.5,
        quantity: 2,
      ),
      const CartItem(
        id: 'cart-2',
        productId: null, // on-the-fly
        name: 'Bolsa Ecológica',
        unitPriceMxn: 5.0,
        quantity: 1,
        isOnTheFly: true,
      ),
    ];

    final testPayments = [
      const PaymentEntry(
        id: 'pay-1',
        method: PaymentMethodMxn.cashMxn,
        amountMxn: 50.0,
      ),
    ];

    test('envía payload correcto y retorna CheckoutResult exitoso', () async {
      final mockResponseData = {
        'sale_id': 'f0000000-0000-0000-0000-000000000001',
        'folio': 'NV-2026-000001',
        'total_usd': 42.0,
        'total_paid_usd': 50.0,
        'change_given_usd': 8.0,
        'total_mxn': 42.0,
        'total_paid_mxn': 50.0,
        'change_given_mxn': 8.0,
        'status': 'COMPLETED',
        'items_count': 2,
        'completed_at': '2026-09-14T12:00:00.000Z',
      };

      when(
        () => mockClient.post<dynamic>(
          '/api/v1/sales/checkout',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          data: mockResponseData,
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/v1/sales/checkout'),
        ),
      );

      final result = await repository.checkout(
        items: testItems,
        payments: testPayments,
        cashierName: 'Don Roberto',
      );

      expect(result.saleId, equals('f0000000-0000-0000-0000-000000000001'));
      expect(result.folio, equals('NV-2026-000001'));
      expect(result.totalMxn, equals(42.0));
      expect(result.totalPaidMxn, equals(50.0));
      expect(result.changeGivenMxn, equals(8.0));
      expect(result.cashierName, equals('Don Roberto'));
      expect(result.items.length, equals(2));
      expect(result.payments.length, equals(1));
      expect(repository.sessionSales.length, equals(1));

      // Verificar que el payload incluya los items y pagos
      final captured = verify(
        () => mockClient.post<dynamic>(
          '/api/v1/sales/checkout',
          data: captureAny(named: 'data'),
          options: any(named: 'options'),
        ),
      ).captured.single as Map<String, dynamic>;

      final itemsPayload = captured['items'] as List;
      expect(itemsPayload.length, equals(2));
      expect(itemsPayload[0]['product_id'], equals('a1111111-b222-c333-d444-e55555555555'));
      expect(itemsPayload[0]['quantity'], equals(2));
      expect(itemsPayload[0]['unit_price_usd'], equals(18.5));
      expect(itemsPayload[1].containsKey('product_id'), isFalse); // on-the-fly no envía product_id

      final paymentsPayload = captured['payments'] as List;
      expect(paymentsPayload.length, equals(1));
      expect(paymentsPayload[0]['payment_method'], equals('CASH_MXN'));
      expect(paymentsPayload[0]['amount_usd'], equals(50.0));
    });

    test('soporta pagos mixtos (Efectivo + SPEI con referencia)', () async {
      final mixedPayments = [
        const PaymentEntry(
          id: 'pay-1',
          method: PaymentMethodMxn.cashMxn,
          amountMxn: 20.0,
        ),
        const PaymentEntry(
          id: 'pay-2',
          method: PaymentMethodMxn.spei,
          amountMxn: 22.0,
          referenceCode: 'SPEI-998877',
        ),
      ];

      when(
        () => mockClient.post<dynamic>(
          '/api/v1/sales/checkout',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          data: {
            'sale_id': 'sale-mixed-123',
            'folio': 'NV-2026-000002',
            'total_usd': 42.0,
            'total_paid_usd': 42.0,
            'change_given_usd': 0.0,
            'status': 'COMPLETED',
            'items_count': 2,
            'completed_at': DateTime.now().toIso8601String(),
          },
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/v1/sales/checkout'),
        ),
      );

      final result = await repository.checkout(
        items: testItems,
        payments: mixedPayments,
        cashierName: 'Cajero 1',
      );

      expect(result.folio, equals('NV-2026-000002'));
      expect(result.changeGivenMxn, equals(0.0));

      final captured = verify(
        () => mockClient.post<dynamic>(
          '/api/v1/sales/checkout',
          data: captureAny(named: 'data'),
          options: any(named: 'options'),
        ),
      ).captured.single as Map<String, dynamic>;

      final paymentsPayload = captured['payments'] as List;
      expect(paymentsPayload.length, equals(2));
      expect(paymentsPayload[1]['payment_method'], equals('SPEI'));
      expect(paymentsPayload[1]['reference_number'], equals('SPEI-998877'));
    });

    test('lanza SalesException con mensaje del backend cuando hay stock insuficiente', () async {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/api/v1/sales/checkout'),
        response: Response(
          statusCode: 400,
          data: {
            'detail': {
              'code': 'INSUFFICIENT_STOCK',
              'message': "Stock insuficiente para el producto 'Coca Cola 600ml'. Solicitado: 5, Disponible: 1.",
            },
          },
          requestOptions: RequestOptions(path: '/api/v1/sales/checkout'),
        ),
        type: DioExceptionType.badResponse,
      );

      when(
        () => mockClient.post<dynamic>(
          '/api/v1/sales/checkout',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(dioError);

      expect(
        () => repository.checkout(
          items: testItems,
          payments: testPayments,
          cashierName: 'Cajero',
        ),
        throwsA(
          isA<SalesException>().having(
            (e) => e.message,
            'message',
            contains('Stock insuficiente'),
          ),
        ),
      );
    });

    test('lanza SalesException cuando ocurre error de red/timeout', () async {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/api/v1/sales/checkout'),
        type: DioExceptionType.connectionTimeout,
        message: 'Connection timed out',
      );

      when(
        () => mockClient.post<dynamic>(
          '/api/v1/sales/checkout',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(dioError);

      expect(
        () => repository.checkout(
          items: testItems,
          payments: testPayments,
          cashierName: 'Cajero',
        ),
        throwsA(
          isA<SalesException>().having(
            (e) => e.message,
            'message',
            contains('Sin conexión con el servidor'),
          ),
        ),
      );
    });
  });
}
