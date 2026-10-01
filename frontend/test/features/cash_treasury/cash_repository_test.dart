// Importación del paquete Dio para manejo de respuestas y excepciones HTTP
import 'package:dio/dio.dart';
// Importación del framework de pruebas de Flutter
import 'package:flutter_test/flutter_test.dart';
// Importación de Mocktail para simular dependencias de red
import 'package:mocktail/mocktail.dart';
// Importación del cliente centralizado DioClient
import 'package:nexus_app/core/network/dio_client.dart';
// Importación del repositorio de caja y sus implementaciones
import 'package:nexus_app/features/cash_treasury/data/cash_repository.dart';
// Importación del catálogo oficial de denominaciones Banxico
import 'package:nexus_app/features/cash_treasury/domain/banxico_denomination.dart';
// Importación del modelo de entidad de turno de caja
import 'package:nexus_app/features/cash_treasury/domain/cash_session.dart';

// ---------------------------------------------------------------------------
// Mock de DioClient para pruebas unitarias aisladas sin red
// ---------------------------------------------------------------------------

class MockDioClient extends Mock implements DioClient {}

void main() {
  // Cliente simulado
  late MockDioClient mockClient;
  // Instancia bajo prueba
  late CashRepositoryImpl repository;

  setUp(() {
    mockClient = MockDioClient();
    repository = CashRepositoryImpl(client: mockClient);
  });

  group('CashRepositoryImpl — openSession()', () {
    test('envía apertura con fondo inicial y retorna CashSession abierta', () async {
      // Configuración de respuesta simulada del backend FastAPI
      final mockResponse = {
        'id': 'shift-uuid-001',
        'cashier_id': 'user-uuid-123',
        'cashier_name': 'Ana García',
        'status': 'OPEN',
        'opening_amount_mxn': 500.0,
        'expected_cash_mxn': 500.0,
        'opened_at': '2026-09-17T08:00:00.000Z',
      };

      when(
        () => mockClient.post<dynamic>(
          '/api/v1/cash/open-session',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          data: mockResponse,
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/v1/cash/open-session'),
        ),
      );

      // Invocación del método de repositorio
      final session = await repository.openSession(
        cashierName: 'Ana García',
        openingAmountMxn: 500.0,
      );

      // Verificaciones de aserción
      expect(session.id, equals('shift-uuid-001'));
      expect(session.cashierName, equals('Ana García'));
      expect(session.status, equals(CashSessionStatus.open));
      expect(session.openingAmountMxn, equals(500.0));
      expect(session.expectedCashMxn, equals(500.0));
    });

    test('lanza CashException si el backend retorna error 409 (conflicto turno existente)', () async {
      // Simulación de error de turno ya abierto
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/api/v1/cash/open-session'),
        response: Response(
          statusCode: 409,
          data: {'detail': 'Ya existe un turno de caja abierto para este usuario.'},
          requestOptions: RequestOptions(path: '/api/v1/cash/open-session'),
        ),
        type: DioExceptionType.badResponse,
      );

      when(
        () => mockClient.post<dynamic>(
          '/api/v1/cash/open-session',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(dioError);

      // Verificación de lanzamiento de excepción de dominio
      expect(
        () => repository.openSession(cashierName: 'Ana', openingAmountMxn: 500.0),
        throwsA(isA<CashException>().having(
          (e) => e.message,
          'message',
          contains('Ya existe un turno'),
        )),
      );
    });
  });

  group('CashRepositoryImpl — closeSession()', () {
    test('envía conteo de denominaciones Banxico y retorna sesión cerrada con balance', () async {
      // Sesión activa previa
      final activeSession = CashSession(
        id: 'shift-uuid-001',
        cashierName: 'Ana García',
        status: CashSessionStatus.open,
        openingAmountMxn: 500.0,
        expectedCashMxn: 700.0,
        openedAt: DateTime.now(),
      );

      // Conteo físico de 7 billetes de 100
      const count = BanxicoCount({'bills_100': 7});

      final mockResponse = {
        'shift_id': 'shift-uuid-001',
        'status': 'CLOSED',
        'expected_cash_mxn': 700.0,
        'physical_cash_mxn': 700.0,
        'difference_mxn': 0.0,
        'balance_result': 'EXACT',
        'closed_at': '2026-09-17T18:00:00.000Z',
      };

      when(
        () => mockClient.post<dynamic>(
          '/api/v1/cash/close-session',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          data: mockResponse,
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/v1/cash/close-session'),
        ),
      );

      final result = await repository.closeSession(
        session: activeSession,
        physicalDenominations: count,
      );

      expect(result.status, equals(CashSessionStatus.closed));
      expect(result.physicalCashMxn, equals(700.0));
      expect(result.differenceMxn, equals(0.0));
      expect(result.balanceResult, equals(CashBalanceResult.exact));

      // Verificar que el payload contiene el desglose Banxico de 12 denominaciones
      final captured = verify(
        () => mockClient.post<dynamic>(
          '/api/v1/cash/close-session',
          data: captureAny(named: 'data'),
          options: any(named: 'options'),
        ),
      ).captured.single as Map<String, dynamic>;

      expect(captured['shift_id'], equals('shift-uuid-001'));
      final denoms = captured['physical_denominations'] as Map<String, dynamic>;
      expect(denoms['bills_100'], equals(7));
      expect(denoms['bills_1000'], equals(0));
    });
  });

  // Integración de Caja (Oct 2026): respuestas reales del servidor
  group('CashRepositoryImpl — respuestas reales', () {
    void answer(String path, dynamic data, {bool post = true, int status = 200}) {
      final response = Response(data: data, statusCode: status, requestOptions: RequestOptions(path: path));
      if (post) {
        when(() => mockClient.post<dynamic>(path, data: any(named: 'data'), options: any(named: 'options')))
            .thenAnswer((_) async => response);
      } else {
        when(() => mockClient.get<dynamic>(path, queryParameters: any(named: 'queryParameters'), options: any(named: 'options')))
            .thenAnswer((_) async => response);
      }
    }

    test('el cierre viene anidado {session, balance_summary}: se lee el faltante real (A2)', () async {
      answer('/api/v1/cash/close-session', {
        'session': {
          'id': 'shift-1', 'cashier_name': 'Rosa', 'status': 'CLOSED', 'opening_amount_mxn': '600.00',
          'expected_cash_mxn': '536.00', 'physical_cash_mxn': '530.00', 'difference_mxn': '-6.00',
          'balance_result': 'SHORT', 'opened_at': '2026-10-01T08:00:00Z', 'closed_at': '2026-10-01T18:00:00Z',
          'summary': {'cash_sales_mxn': '36.00', 'deposits_mxn': '0.00', 'withdrawals_mxn': '100.00',
                      'digital_totals_mxn': {'CARD_TPV': '18.00'}, 'sales_count': 2, 'sales_total_mxn': '54.00', 'movements_count': 1},
        },
        'balance_summary': {'expected_cash_mxn': '536.00', 'physical_cash_mxn': '530.00', 'difference_mxn': '-6.00',
                            'balance_result': 'SHORT', 'sales_count': 2},
      });
      final closed = await repository.closeSession(
        session: CashSession(id: 'shift-1', cashierName: 'Rosa', status: CashSessionStatus.open,
            openingAmountMxn: 600, expectedCashMxn: 600, openedAt: DateTime(2026, 10, 1, 8)),
        physicalDenominations: const BanxicoCount({'bills_500': 1, 'bills_20': 1, 'coins_10': 1}),
      );
      expect(closed.status, CashSessionStatus.closed);
      expect(closed.expectedCashMxn, 536.0);
      expect(closed.differenceMxn, -6.0);
      expect(closed.balanceResult, CashBalanceResult.short);
      expect(closed.summary!.digitalTotalsMxn, {'CARD_TPV': 18.0});
    });

    test('el turno activo trae el resumen del servidor', () async {
      answer('/api/v1/cash/active-session', {
        'id': 'shift-2', 'cashier_name': 'Rosa', 'status': 'OPEN', 'opening_amount_mxn': '600.00',
        'expected_cash_mxn': '586.00', 'opened_at': '2026-10-01T08:00:00Z',
        'summary': {'cash_sales_mxn': '36.00', 'deposits_mxn': '50.00', 'withdrawals_mxn': '100.00',
                    'digital_totals_mxn': {'SPEI': '18.00'}, 'sales_count': 2, 'sales_total_mxn': '54.00', 'movements_count': 2},
      }, post: false);
      final session = (await repository.getActiveSession())!;
      expect(session.expectedCashMxn, 586.0);
      expect(session.summary!.cashSalesMxn, 36.0);
      expect(session.summary!.salesCount, 2);
    });

    test('"Ya tienes una sesión de caja activa" se distingue para retomarla (A1)', () async {
      final options = RequestOptions(path: '/api/v1/cash/open-session');
      when(() => mockClient.post<dynamic>('/api/v1/cash/open-session', data: any(named: 'data'), options: any(named: 'options')))
          .thenThrow(DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 422,
            data: {'detail': 'Ya tienes una sesión de caja activa. Ciérrala antes de abrir una nueva.'}),
        type: DioExceptionType.badResponse,
      ));
      await expectLater(
        repository.openSession(cashierName: 'Rosa', openingAmountMxn: 100),
        throwsA(isA<CashSessionAlreadyOpen>()),
      );
    });
  });
}
