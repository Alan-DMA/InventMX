import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../domain/employee_performance.dart';
import 'models/json_number.dart';

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
  /// Rendimiento y comisiones del vendedor en sesión durante el mes natural
  /// [month] (sólo cuentan año y mes).
  Future<EmployeePerformance> getPerformance({
    required String cashierName,
    required DateTime month,
  });
}

// ---------------------------------------------------------------------------
// Implementación Real (Conexión Directa a la API FastAPI / PostgreSQL)
// ---------------------------------------------------------------------------

const _kMonthNames = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

/// "Septiembre 2026" — etiqueta del selector de período y del encabezado.
String monthLabel(DateTime month) => '${_kMonthNames[month.month - 1]} ${month.year}';

/// `YYYY-MM` para el query param `period_month`.
String periodMonthParam(DateTime month) =>
    '${month.year}-${month.month.toString().padLeft(2, '0')}';

/// Repositorio real que consume `GET /api/v1/analytics/commissions`.
///
/// El endpoint sólo devuelve datos del usuario en sesión (`current_user`,
/// `summary`, `daily_breakdown`, `history`): nada de otros vendedores. Los
/// montos llegan como `num` (devuelve un `dict`, no un `response_model`),
/// pero se leen con los helpers tolerantes por si Alan lo tipa después.
class CommissionsRepositoryImpl implements CommissionsRepository {
  /// Constructor con inyección del cliente HTTP DioClient
  CommissionsRepositoryImpl({required this.client});

  /// Cliente de red configurado
  final DioClient client;

  @override
  Future<EmployeePerformance> getPerformance({
    required String cashierName,
    required DateTime month,
  }) async {
    try {
      final response = await client.get(
        '/api/v1/analytics/commissions',
        queryParameters: {'period_month': periodMonthParam(month)},
      );

      final dynamic data = response.data;
      if (data == null || data is! Map) {
        throw const CommissionsException('Respuesta inválida del servidor de comisiones.');
      }

      // Quién soy y con qué esquema comisiono (lo dice el servidor, no la app)
      final current = data['current_user'];
      final displayName = current is Map && current['cashier_name'] != null
          ? current['cashier_name'].toString()
          : cashierName;
      final role = current is Map && current['role'] != null
          ? _roleLabel(current['role'].toString())
          : 'Vendedor';
      final commissionType = CommissionType.fromApi(
          current is Map ? current['commission_type']?.toString() : null);
      final commissionRate =
          toDoubleOrZero(current is Map ? current['commission_rate'] : null);

      // Totales del período: `summary` es sólo del usuario en sesión.
      final summary = data['summary'];
      final totalSales =
          toDoubleOrZero(summary is Map ? summary['total_sales_mxn'] : null);
      final earned = toDoubleOrZero(
          summary is Map ? summary['earned_commission_mxn'] : null);

      // Histórico personal: `month` viene como YYYY-MM.
      final history = (data['history'] as List? ?? const [])
          .whereType<Map>()
          .map((h) {
            final parts = h['month']?.toString().split('-') ?? const <String>[];
            final year = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
            final mon = parts.length > 1 ? int.tryParse(parts[1]) : null;
            if (year == null || mon == null) return null;
            return MonthlyCommissionEntry(
              month: DateTime(year, mon),
              salesCount: toIntOrZero(h['sales_count']),
              commissionMxn: toDoubleOrZero(h['commission_mxn']),
            );
          })
          .whereType<MonthlyCommissionEntry>()
          .toList();

      final daily = (data['daily_breakdown'] as List? ?? const [])
          .whereType<Map>()
          .map((d) => DailyCommissionEntry(
                date: toDateTimeOrNull(d['date']) ?? DateTime.now(),
                salesCount: toIntOrZero(d['sales_count']),
                commissionMxn: toDoubleOrZero(d['commission_mxn']),
              ))
          .toList();

      return EmployeePerformance(
        cashierName: displayName,
        role: role,
        periodLabel: monthLabel(month),
        totalSalesMxn: totalSales,
        accumulatedCommissionMxn: earned,
        commissionRatePercent: commissionRate,
        commissionType: commissionType,
        dailyBreakdown: daily,
        history: history,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is CommissionsException) rethrow;
      throw CommissionsException('Error al cargar comisiones: $e');
    }
  }

  static String _roleLabel(String role) => switch (role.toUpperCase()) {
        'OWNER' => 'Dueño',
        'ADMIN' || 'MANAGER' => 'Administrador',
        'CASHIER' => 'Cajero',
        'WAREHOUSE' || 'STOCKER' => 'Almacenista',
        _ => 'Vendedor',
      };

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
