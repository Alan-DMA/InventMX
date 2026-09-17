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
      final count = const BanxicoCount({'bills_100': 7});

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
}
