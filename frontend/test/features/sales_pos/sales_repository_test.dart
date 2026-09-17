import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockDioClient extends Mock implements DioClient {}

void main() {
  late MockDioClient mockClient;
  late SalesRepositoryImpl repository;

  setUp(() {
    mockClient = MockDioClient();
    repository = SalesRepositoryImpl(client: mockClient);
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
