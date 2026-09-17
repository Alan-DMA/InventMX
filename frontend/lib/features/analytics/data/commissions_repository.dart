import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../../sales_pos/data/sales_repository.dart';
import '../../sales_pos/domain/cart_state.dart';
import '../domain/employee_performance.dart';

// ---------------------------------------------------------------------------
// Excepción de dominio para Comisiones y Analíticas
// ---------------------------------------------------------------------------

/// Excepción especializada para errores del módulo de comisiones
class CommissionsException implements Exception {
  /// Constructor con mensaje descriptivo
  const CommissionsException(this.message);
  /// Mensaje de error
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

abstract class CommissionsRepository {
  /// Consulta el rendimiento y comisiones acumuladas del vendedor en sesión
  Future<EmployeePerformance> getPerformance({required String cashierName});
}

// ---------------------------------------------------------------------------
// Implementación Real (Conexión Directa a la API FastAPI / PostgreSQL)
// ---------------------------------------------------------------------------

/// Repositorio real que consume `GET /api/v1/analytics/commissions`
class CommissionsRepositoryImpl implements CommissionsRepository {
  /// Constructor con inyección del cliente HTTP DioClient
  CommissionsRepositoryImpl({required this.client});

  /// Cliente de red configurado
  final DioClient client;

  @override
  Future<EmployeePerformance> getPerformance({
    required String cashierName,
  }) async {
    try {
      // Petición HTTP GET al endpoint canónico de FastAPI
      final response = await client.get('/api/v1/analytics/commissions');

      // Validación de payload JSON
      final dynamic data = response.data;
      if (data == null || data is! Map) {
        throw const CommissionsException('Respuesta inválida del servidor de comisiones.');
      }

      // Procesamiento de lista de ranking
      final rawRanking = (data['ranking'] as List? ?? []);
      final ranking = rawRanking.map((item) {
        final map = item as Map;
        final name = map['cashier_name']?.toString() ?? 'Vendedor';
        final commission = (map['commission_mxn'] as num?)?.toDouble() ?? 0.0;
        final isCurrent = map['is_current_user'] == true ||
            name.toLowerCase() == cashierName.toLowerCase();
        return RankingEntry(
          cashierName: name,
          commissionMxn: commission,
          isCurrentUser: isCurrent,
        );
      }).toList();

      // Búsqueda del cajero actual dentro de la lista de cashiers
      final rawCashiers = (data['cashiers'] as List? ?? []);
      Map<dynamic, dynamic>? matched;
      for (final c in rawCashiers) {
        if (c is Map && c['cashier_name']?.toString().toLowerCase() == cashierName.toLowerCase()) {
          matched = c;
          break;
        }
      }

      final totalSalesMxn = (matched?['total_sales_mxn'] as num?)?.toDouble() ?? 0.0;
      final accumulatedCommissionMxn = (matched?['earned_commission_mxn'] as num?)?.toDouble() ??
          (ranking.firstWhere((r) => r.isCurrentUser, orElse: () => RankingEntry(cashierName: cashierName, commissionMxn: 0.0)).commissionMxn);

      final periodMonth = data['period']?.toString() ?? DateTime.now().toString().substring(0, 7);
      final periodLabel = 'Período · $periodMonth';

      return EmployeePerformance(
        cashierName: cashierName,
        role: 'Vendedor',
        periodLabel: periodLabel,
        totalSalesMxn: totalSalesMxn,
        accumulatedCommissionMxn: accumulatedCommissionMxn,
        commissionRatePercent: 5.0, // Configuración estándar 5%
        dailyBreakdown: const [], // Desglose granular diario
        ranking: ranking,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is CommissionsException) rethrow;
      throw CommissionsException('Error al cargar comisiones: $e');
    }
  }

  /// Mapeo de códigos HTTP de Dio a mensajes comprensibles
  Exception _mapDioError(DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) {
        return CommissionsException(data['detail'].toString());
      }
    }
    switch (e.response?.statusCode) {
      case 401:
        return const CommissionsException('Sesión expirada. Inicie sesión nuevamente.');
      case 403:
        return const CommissionsException('No tiene permisos para ver comisiones.');
      case 500:
      case 502:
      case 503:
        return const CommissionsException('Servidor no disponible. Intente más tarde.');
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          return const CommissionsException('Sin conexión con el servidor. Verifique su red.');
        }
        return CommissionsException('Error de red: ${e.message ?? e.type.name}');
    }
  }
}

// ---------------------------------------------------------------------------
// Mock — activo para pruebas offline o widget tests
// ---------------------------------------------------------------------------

class CommissionsRepositoryMock implements CommissionsRepository {
  static const _fakeDelay = Duration(milliseconds: 100);

  /// Tasa dinámica configurable por vendedor (RF-10) — fija en el Mock.
  static const _commissionRatePercent = 5.0;

  /// Vendedores de referencia para poblar el ranking mientras no exista un
  /// backend multi-usuario real (Alan, Tarea 2.1 RBAC / 8.1.3 comisiones).
  static const _peerSeed = [
    ('María López', 62.00),
    ('Juan Torres', 31.50),
  ];

  @override
  Future<EmployeePerformance> getPerformance({
    required String cashierName,
  }) async {
    await Future.delayed(_fakeDelay);

    final mySales = SalesRepositoryMock.todaysSales
        .where((s) => s.cashierName == cashierName)
        .toList();

    final totalSalesMxn =
        mySales.fold(0.0, (sum, s) => sum + s.totalMxn);
    final accumulatedCommissionMxn =
        totalSalesMxn * (_commissionRatePercent / 100);

    final dailyBreakdown = _groupByDay(mySales);

    final ranking = <RankingEntry>[
      RankingEntry(
        cashierName: cashierName,
        commissionMxn: accumulatedCommissionMxn,
        isCurrentUser: true,
      ),
      for (final (name, commissionMxn) in _peerSeed)
        RankingEntry(cashierName: name, commissionMxn: commissionMxn),
    ]..sort((a, b) => b.commissionMxn.compareTo(a.commissionMxn));

    final today = DateTime.now();
    final periodLabel =
        'Hoy · ${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';

    return EmployeePerformance(
      cashierName: cashierName,
      role: 'Vendedor',
      periodLabel: periodLabel,
      totalSalesMxn: totalSalesMxn,
      accumulatedCommissionMxn: accumulatedCommissionMxn,
      commissionRatePercent: _commissionRatePercent,
      dailyBreakdown: dailyBreakdown,
      ranking: ranking,
    );
  }

  List<DailyCommissionEntry> _groupByDay(List<CheckoutResult> sales) {
    final byDay = <DateTime, List<CheckoutResult>>{};
    for (final sale in sales) {
      final day = DateTime(
        sale.completedAt.year,
        sale.completedAt.month,
        sale.completedAt.day,
      );
      byDay.putIfAbsent(day, () => []).add(sale);
    }

    final entries = byDay.entries.map((entry) {
      final daySalesTotal =
          entry.value.fold(0.0, (sum, s) => sum + s.totalMxn);
      return DailyCommissionEntry(
        date: entry.key,
        salesCount: entry.value.length,
        commissionMxn: daySalesTotal * (_commissionRatePercent / 100),
      );
    }).toList();

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }
}
