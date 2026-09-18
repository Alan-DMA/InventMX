import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../domain/banxico_denomination.dart';
import '../domain/cash_movement.dart';
import '../domain/cash_session.dart';

/// Los montos del backend viajan como `Decimal` de Python — Pydantic los
/// serializa como string ("500.00") para no perder precisión, no como
/// número JSON. Un cast directo a `num?` truena con ese payload real.
double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

// ---------------------------------------------------------------------------
// Excepción de dominio para Caja y Tesorería
// ---------------------------------------------------------------------------

/// Excepción especializada para capturar y presentar errores del módulo de caja
class CashException implements Exception {
  /// Constructor con mensaje explicativo
  const CashException(this.message);
  /// Mensaje de error para el usuario o log
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

abstract class CashRepository {
  /// Apertura de turno de caja vía `POST /api/v1/cash/open-session`.
  Future<CashSession> openSession({
    required String cashierName,
    required double openingAmountMxn,
    BanxicoCount? openingDenominations,
  });

  /// Cierre de turno de caja vía `POST /api/v1/cash/close-session`.
  /// [session] debe traer el identificador del turno y el saldo teórico.
  Future<CashSession> closeSession({
    required CashSession session,
    required BanxicoCount physicalDenominations,
  });

  /// Consulta de turno activo vía `GET /api/v1/cash/active-session`.
  Future<CashSession?> getActiveSession();

  /// Consulta de movimientos del turno vía `GET /api/v1/cash/sessions/{id}/movements`.
  Future<List<CashMovement>> listMovements(String sessionId);

  /// Registro de movimiento extraordinario vía `POST /api/v1/cash/sessions/{id}/movements`.
  Future<CashMovement> addMovement({
    required String sessionId,
    required CashMovementType type,
    required double amountMxn,
    required String description,
  });
}

// ---------------------------------------------------------------------------
// Implementación Real (Conexión Directa a la API FastAPI / PostgreSQL)
// ---------------------------------------------------------------------------

/// Implementación real que se conecta a los endpoints `/api/v1/cash/*` del backend Nexus
class CashRepositoryImpl implements CashRepository {
  /// Constructor con cliente Dio inyectado
  CashRepositoryImpl({required this.client});

  /// Instancia de cliente de red Dio
  final DioClient client;

  @override
  Future<CashSession> openSession({
    required String cashierName,
    required double openingAmountMxn,
    BanxicoCount? openingDenominations,
  }) async {
    try {
      // Construcción del payload JSON conforme a la especificación OpenAPI
      final payload = <String, dynamic>{
        'opening_amount_mxn': openingAmountMxn,
        if (openingDenominations != null)
          'opening_denominations': openingDenominations.toJson(),
      };

      // Ejecución de la petición HTTP POST hacia el backend
      final response = await client.post(
        '/api/v1/cash/open-session',
        data: payload,
      );

      // Validación de formato de respuesta
      final dynamic data = response.data;
      if (data == null || data is! Map) {
        throw const CashException('Respuesta inválida del servidor al abrir turno de caja.');
      }

      // Mapeo a entidad de dominio CashSession
      return _mapSession(data, fallbackCashierName: cashierName);
    } on DioException catch (e) {
      // Mapeo de errores HTTP/Dio
      throw _mapDioError(e);
    } catch (e) {
      // Manejo de excepciones genéricas
      if (e is CashException) rethrow;
      throw CashException('Error inesperado al abrir turno de caja: $e');
    }
  }

  @override
  Future<CashSession> closeSession({
    required CashSession session,
    required BanxicoCount physicalDenominations,
  }) async {
    try {
      // Construcción del payload para cierre con desglose de denominaciones Banxico
      final payload = <String, dynamic>{
        'shift_id': session.id,
        'physical_denominations': physicalDenominations.toJson(),
        'notes': 'Cierre de turno desde TPV Nexus',
      };

      // Ejecución de la petición HTTP POST hacia el backend
      final response = await client.post(
        '/api/v1/cash/close-session',
        data: payload,
      );

      // Validación de formato de respuesta
      final dynamic data = response.data;
      if (data == null || data is! Map) {
        throw const CashException('Respuesta inválida del servidor al cerrar turno de caja.');
      }

      // Extracción del resultado del arqueo y balance
      final statusStr = data['status']?.toString().toLowerCase() ?? 'closed';
      final balanceStr = data['balance_result']?.toString().toLowerCase() ?? 'exact';
      final closedAtStr = data['closed_at']?.toString();

      // Retorno de la sesión actualizada con datos calculados del backend
      return session.copyWith(
        status: statusStr == 'open' ? CashSessionStatus.open : CashSessionStatus.closed,
        expectedCashMxn: _toDouble(data['expected_cash_mxn']) ?? session.expectedCashMxn,
        physicalCashMxn: _toDouble(data['physical_cash_mxn']) ?? physicalDenominations.totalMxn,
        differenceMxn: _toDouble(data['difference_mxn']) ?? 0.0,
        balanceResult: balanceStr == 'short'
            ? CashBalanceResult.short
            : (balanceStr == 'over' ? CashBalanceResult.over : CashBalanceResult.exact),
        closedAt: closedAtStr != null ? DateTime.tryParse(closedAtStr) ?? DateTime.now() : DateTime.now(),
      );
    } on DioException catch (e) {
      // Mapeo de errores de red
      throw _mapDioError(e);
    } catch (e) {
      // Propagación o envoltura
      if (e is CashException) rethrow;
      throw CashException('Error inesperado al cerrar turno de caja: $e');
    }
  }

  @override
  Future<CashSession?> getActiveSession() async {
    try {
      // Consulta del turno activo del usuario autenticado
      final response = await client.get('/api/v1/cash/active-session');
      final dynamic data = response.data;
      if (data == null || data is! Map) return null;
      return _mapSession(data);
    } on DioException catch (e) {
      // 404 significa que no hay sesión abierta actualmente (estado normal)
      if (e.response?.statusCode == 404) return null;
      throw _mapDioError(e);
    } catch (e) {
      if (e is CashException) rethrow;
      throw CashException('Error al consultar turno de caja activo: $e');
    }
  }

  @override
  Future<List<CashMovement>> listMovements(String sessionId) async {
    try {
      final response = await client.get('/api/v1/cash/sessions/$sessionId/movements');
      final dynamic data = response.data;
      if (data == null || data is! List) return const [];
      return data.map((e) {
        final map = e as Map<String, dynamic>;
        final typeStr = map['type']?.toString().toUpperCase();
        return CashMovement(
          id: map['id']?.toString() ?? '',
          cashSessionId: sessionId,
          type: typeStr == 'DEPOSIT'
              ? CashMovementType.deposit
              : CashMovementType.withdrawal,
          amountMxn: _toDouble(map['amount_mxn']) ?? 0.0,
          description: map['description']?.toString() ?? '',
          createdAt: map['created_at'] != null
              ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
              : DateTime.now(),
        );
      }).toList();
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is CashException) rethrow;
      throw CashException('Error al listar movimientos de caja: $e');
    }
  }

  @override
  Future<CashMovement> addMovement({
    required String sessionId,
    required CashMovementType type,
    required double amountMxn,
    required String description,
  }) async {
    try {
      final response = await client.post(
        '/api/v1/cash/sessions/$sessionId/movements',
        data: {
          'type': type.apiValue,
          'amount_mxn': amountMxn,
          'description': description,
        },
      );
      final dynamic data = response.data;
      if (data == null || data is! Map) {
        throw const CashException('Respuesta inválida al registrar movimiento.');
      }
      return CashMovement(
        id: data['id']?.toString() ?? 'mov-${DateTime.now().millisecondsSinceEpoch}',
        cashSessionId: sessionId,
        type: type,
        amountMxn: amountMxn,
        description: description,
        createdAt: data['created_at'] != null
            ? DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is CashException) rethrow;
      throw CashException('Error al registrar movimiento: $e');
    }
  }

  /// Transforma un mapa JSON proveniente de FastAPI a la entidad CashSession
  CashSession _mapSession(Map<dynamic, dynamic> data, {String? fallbackCashierName}) {
    // Normalización de estado en minúsculas
    final statusStr = data['status']?.toString().toLowerCase() ?? 'open';
    final balanceStr = data['balance_result']?.toString().toLowerCase();

    // Mapeo campo por campo
    return CashSession(
      id: data['id']?.toString() ?? 'cash-unknown',
      cashierName: data['cashier_name']?.toString() ?? fallbackCashierName ?? 'Cajero',
      status: statusStr == 'closed' ? CashSessionStatus.closed : CashSessionStatus.open,
      openingAmountMxn: _toDouble(data['opening_amount_mxn']) ?? 0.0,
      expectedCashMxn: _toDouble(data['expected_cash_mxn']) ?? 0.0,
      physicalCashMxn: _toDouble(data['physical_cash_mxn']),
      differenceMxn: _toDouble(data['difference_mxn']),
      balanceResult: balanceStr == null
          ? null
          : (balanceStr == 'short'
              ? CashBalanceResult.short
              : (balanceStr == 'over' ? CashBalanceResult.over : CashBalanceResult.exact)),
      openedAt: data['opened_at'] != null
          ? DateTime.tryParse(data['opened_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      closedAt: data['closed_at'] != null
          ? DateTime.tryParse(data['closed_at'].toString())
          : null,
    );
  }

  /// Traduce los errores de Dio a mensajes de dominio legibles para el cajero
  Exception _mapDioError(DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map) {
        if (data['detail'] is Map && data['detail']['message'] != null) {
          return CashException(data['detail']['message'].toString());
        }
        if (data['error'] is Map && data['error']['message'] != null) {
          return CashException(data['error']['message'].toString());
        }
        if (data['detail'] != null && data['detail'] is String) {
          return CashException(data['detail'].toString());
        }
      }
    }

    switch (e.response?.statusCode) {
      case 400:
        return const CashException('Datos de turno inválidos o inconsistentes.');
      case 401:
        return const CashException('Sesión expirada. Inicie sesión nuevamente.');
      case 403:
        return const CashException('No tiene permisos para operar la caja registradora.');
      case 404:
        return const CashException('Turno de caja no encontrado.');
      case 409:
        return const CashException('Ya existe un turno de caja abierto para este usuario.');
      case 422:
        return const CashException('Error de validación en los importes de denominaciones.');
      case 500:
      case 502:
      case 503:
        return const CashException('Servidor no disponible. Intente más tarde.');
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          return const CashException('Sin conexión con el servidor. Verifique su red.');
        }
        return CashException('Error de red: ${e.message ?? e.type.name}');
    }
  }
}

// ---------------------------------------------------------------------------
// Mock — activo para pruebas offline o tests unitarios de UI
// ---------------------------------------------------------------------------

class CashRepositoryMock implements CashRepository {
  static const _fakeDelay = Duration(milliseconds: 100);

  /// Fondo inicial fijo de la sesión simulada — no existe todavía una UI de
  /// apertura real (fuera de alcance de la Tarea 9.2, ver plan aprobado).
  /// Mismo valor usado en el ejemplo de `docs/api/cash.yaml`.
  static const defaultOpeningAmountMxn = 500.0;

  static int _sessionCounter = 0;
  static int _movementCounter = 0;

  /// Movimientos de caja menor por sesión — vive en memoria para pruebas offline.
  /// Clave: `CashSession.id`.
  static final Map<String, List<CashMovement>> _movementsBySession = {};

  /// Acceso síncrono usado por `_computeExpectedCashMxn` y `CashMovementsNotifier.build()`.
  static List<CashMovement> movementsFor(String sessionId) =>
      List.unmodifiable(_movementsBySession[sessionId] ?? const []);

  @override
  Future<CashSession> openSession({
    required String cashierName,
    required double openingAmountMxn,
    BanxicoCount? openingDenominations,
  }) async {
    await Future.delayed(_fakeDelay);

    return CashSession(
      id: 'cash-${++_sessionCounter}',
      cashierName: cashierName,
      status: CashSessionStatus.open,
      openingAmountMxn: openingAmountMxn,
      expectedCashMxn: openingAmountMxn,
      openedAt: DateTime.now(),
    );
  }

  @override
  Future<CashSession> closeSession({
    required CashSession session,
    required BanxicoCount physicalDenominations,
  }) async {
    await Future.delayed(_fakeDelay);

    final physicalCashMxn = physicalDenominations.totalMxn;
    final differenceMxn = physicalCashMxn - session.expectedCashMxn;

    final balanceResult = differenceMxn.abs() < 0.005
        ? CashBalanceResult.exact
        : (differenceMxn < 0 ? CashBalanceResult.short : CashBalanceResult.over);

    return session.copyWith(
      status: CashSessionStatus.closed,
      physicalCashMxn: physicalCashMxn,
      differenceMxn: differenceMxn,
      balanceResult: balanceResult,
      closedAt: DateTime.now(),
    );
  }

  @override
  Future<CashSession?> getActiveSession() async {
    await Future.delayed(_fakeDelay);
    return null;
  }

  @override
  Future<List<CashMovement>> listMovements(String sessionId) async {
    await Future.delayed(_fakeDelay);
    return movementsFor(sessionId);
  }

  @override
  Future<CashMovement> addMovement({
    required String sessionId,
    required CashMovementType type,
    required double amountMxn,
    required String description,
  }) async {
    await Future.delayed(_fakeDelay);

    final movement = CashMovement(
      id: 'mov-${++_movementCounter}',
      cashSessionId: sessionId,
      type: type,
      amountMxn: amountMxn,
      description: description,
      createdAt: DateTime.now(),
    );

    final list = _movementsBySession.putIfAbsent(sessionId, () => []);
    list.insert(0, movement);

    return movement;
  }
}
