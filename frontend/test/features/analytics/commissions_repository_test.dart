// Importación del paquete Dio para manejo de respuestas y errores HTTP
import 'package:dio/dio.dart';
// Importación del framework de pruebas de Flutter
import 'package:flutter_test/flutter_test.dart';
// Importación de Mocktail para simular dependencias de red
import 'package:mocktail/mocktail.dart';
// Importación del cliente centralizado DioClient
import 'package:nexus_app/core/network/dio_client.dart';
// Importación del repositorio de comisiones y sus implementaciones
import 'package:nexus_app/features/analytics/data/commissions_repository.dart';

// ---------------------------------------------------------------------------
// Mock de DioClient para pruebas aisladas sin red
// ---------------------------------------------------------------------------

class MockDioClient extends Mock implements DioClient {}

void main() {
  late MockDioClient mockClient;
  late CommissionsRepositoryImpl repository;

  setUp(() {
    mockClient = MockDioClient();
    repository = CommissionsRepositoryImpl(client: mockClient);
  });

  group('CommissionsRepositoryImpl — getPerformance()', () {
    test('consume GET /api/v1/analytics/commissions y mapea ranking y totales correctamente', () async {
      // Configuración de respuesta simulada del backend FastAPI
      final mockResponse = {
        'period': '2026-09',
        'total_commissions_mxn': 48.20,
        'total_sales_count': 14,
        'cashiers': [
          {
            'cashier_id': 'user-123',
            'cashier_name': 'Ana García',
            'total_sales_mxn': 964.0,
            'earned_commission_mxn': 48.20,
            'sales_count': 14,
          },
          {
            'cashier_id': 'user-456',
            'cashier_name': 'Carlos Ruiz',
            'total_sales_mxn': 300.0,
            'earned_commission_mxn': 15.00,
            'sales_count': 5,
          },
        ],
        'ranking': [
          {
            'cashier_name': 'Ana García',
            'commission_mxn': 48.20,
            'is_current_user': true,
          },
          {
            'cashier_name': 'Carlos Ruiz',
            'commission_mxn': 15.00,
            'is_current_user': false,
          },
        ],
      };

      when(
        () => mockClient.get<dynamic>(
          '/api/v1/analytics/commissions',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          data: mockResponse,
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/v1/analytics/commissions'),
        ),
      );

      final performance = await repository.getPerformance(cashierName: 'Ana García');

      expect(performance.cashierName, equals('Ana García'));
      expect(performance.totalSalesMxn, equals(964.0));
      expect(performance.accumulatedCommissionMxn, equals(48.20));
      expect(performance.ranking.length, equals(2));
      expect(performance.ranking.first.cashierName, equals('Ana García'));
      expect(performance.ranking.first.isCurrentUser, isTrue);
    });

    test('lanza CommissionsException si el backend retorna 401 sesión expirada', () async {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/api/v1/analytics/commissions'),
        response: Response(
          statusCode: 401,
          requestOptions: RequestOptions(path: '/api/v1/analytics/commissions'),
        ),
        type: DioExceptionType.badResponse,
      );

      when(
        () => mockClient.get<dynamic>(
          '/api/v1/analytics/commissions',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenThrow(dioError);

      expect(
        () => repository.getPerformance(cashierName: 'Ana'),
        throwsA(isA<CommissionsException>().having(
          (e) => e.message,
          'message',
          contains('Sesión expirada'),
        )),
      );
    });
  });
}
