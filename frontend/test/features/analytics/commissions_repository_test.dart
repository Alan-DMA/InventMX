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
import 'package:nexus_app/features/analytics/domain/employee_performance.dart';

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
    test('consume GET /api/v1/analytics/commissions y mapea summary del usuario en sesión', () async {
      final mockResponse = {
        'period': '2026-09',
        'current_user': {
          'cashier_id': 'user-123',
          'cashier_name': 'Ana García',
          'role': 'OWNER',
          'commission_type': 'PERCENTAGE_SALE',
          'commission_rate': 0,
        },
        'summary': {
          'sales_count': 14,
          'total_sales_mxn': 964.0,
          'earned_commission_mxn': 48.20,
          'pending_settlement_mxn': 48.20,
        },
        'daily_breakdown': [],
        'history': [],
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

      final performance = await repository.getPerformance(cashierName: 'Ana García', month: DateTime(2026, 9));

      expect(performance.cashierName, equals('Ana García'));
      expect(performance.role, 'Dueño');
      expect(performance.totalSalesMxn, equals(964.0));
      expect(performance.accumulatedCommissionMxn, equals(48.20));
      // Sin esquema (tasa 0) y sin histórico todavía.
      expect(performance.hasCommissionScheme, isFalse);
      expect(performance.dailyBreakdown, isEmpty);
      expect(performance.history, isEmpty);
      expect(performance.periodLabel, 'Septiembre 2026');
    });

    test('manda period_month y lee tasa, esquema, rol y desglose diario de current_user', () async {
      Map<String, dynamic>? sentQuery;
      when(
        () => mockClient.get<dynamic>(
          '/api/v1/analytics/commissions',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((inv) async {
        sentQuery = inv.namedArguments[#queryParameters] as Map<String, dynamic>?;
        return Response(
          data: {
            'period': '2026-08',
            'total_commissions_mxn': 12.5,
            'total_sales_count': 2,
            'current_user': {
              'cashier_id': 'user-123',
              'cashier_name': 'Ana García',
              'role': 'CASHIER',
              'commission_type': 'PERCENTAGE_PROFIT',
              'commission_rate': 10,
            },
            'summary': {
              'sales_count': 2,
              'total_sales_mxn': 250.0,
              'earned_commission_mxn': 12.5,
              'pending_settlement_mxn': 12.5,
            },
            'history': [
              {'month': '2026-08', 'sales_count': 2, 'sales_amount_mxn': 250.0, 'commission_mxn': 12.5},
              {'month': '2026-07', 'sales_count': 0, 'sales_amount_mxn': 0, 'commission_mxn': 0},
              {'month': 'basura', 'sales_count': 0, 'commission_mxn': 0},
            ],
            'daily_breakdown': [
              {'date': '2026-08-03', 'sales_count': 2, 'sales_amount_mxn': 250.0, 'commission_mxn': 12.5},
            ],
          },
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/v1/analytics/commissions'),
        );
      });

      final performance = await repository.getPerformance(
        cashierName: 'ana@tienda.mx',
        month: DateTime(2026, 8, 20),
      );

      expect(sentQuery?['period_month'], '2026-08');
      expect(performance.cashierName, 'Ana García'); // el nombre lo da el servidor
      expect(performance.role, 'Cajero');
      expect(performance.commissionType, CommissionType.percentageProfit);
      expect(performance.commissionRatePercent, 10);
      expect(performance.hasCommissionScheme, isTrue);
      expect(performance.commissionType.describe(10), '10% sobre utilidad');
      expect(performance.periodLabel, 'Agosto 2026');
      expect(performance.totalSalesMxn, 250.0);
      expect(performance.accumulatedCommissionMxn, 12.5);
      expect(performance.dailyBreakdown.single.date, DateTime(2026, 8, 3));
      expect(performance.dailyBreakdown.single.salesCount, 2);
      expect(performance.dailyBreakdown.single.commissionMxn, 12.5);
      // Histórico: meses válidos parseados, el inválido se descarta.
      expect(performance.history.length, 2);
      expect(performance.history.first.month, DateTime(2026, 8));
      expect(performance.history.first.commissionMxn, 12.5);
      expect(performance.history.last.month, DateTime(2026, 7));
      expect(performance.history.last.salesCount, 0);
    });

    test('describe() de cada esquema', () {
      expect(CommissionType.percentageSale.describe(5), '5% sobre ventas');
      expect(CommissionType.percentageSale.describe(2.5), '2.50% sobre ventas');
      expect(CommissionType.fixedPerSale.describe(15), r'$15.00 por ticket');
      expect(CommissionType.fromApi('FIXED_PER_SALE'), CommissionType.fixedPerSale);
      expect(CommissionType.fromApi(null), CommissionType.percentageSale);
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
        () => repository.getPerformance(cashierName: 'Ana', month: DateTime(2026, 9)),
        throwsA(isA<CommissionsException>().having(
          (e) => e.message,
          'message',
          contains('Sesión expirada'),
        )),
      );
    });
  });
}
