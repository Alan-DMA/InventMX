import '../domain/banxico_denomination.dart';
import '../domain/cash_movement.dart';
import '../domain/cash_session.dart';

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

abstract class CashRepository {
  /// Equivalente local a `POST /cash/open-session` (Tarea 9.1, pendiente).
  Future<CashSession> openSession({
    required String cashierName,
    required double openingAmountMxn,
  });

  /// Equivalente local a `POST /cash/close-session` (Tarea 9.1, pendiente).
  /// [session] debe traer ya actualizado `expectedCashMxn` (calculado en el
  /// provider a partir de las ventas en efectivo del turno).
  Future<CashSession> closeSession({
    required CashSession session,
    required BanxicoCount physicalDenominations,
  });

  /// Equivalente local a `GET /cash/sessions/{id}/movements` (Tarea 10.1,
  /// pendiente).
  Future<List<CashMovement>> listMovements(String sessionId);

  /// Equivalente local a `POST /cash/sessions/{id}/movements` (Tarea 10.1,
  /// pendiente). La validación de "no exceder el efectivo disponible"
  /// (`422 INSUFFICIENT_CASH_FOR_WITHDRAWAL` en la API) vive en
  /// `CashMovementsNotifier`, no aquí — el repositorio solo persiste.
  Future<CashMovement> addMovement({
    required String sessionId,
    required CashMovementType type,
    required double amountMxn,
    required String description,
  });
}

// ---------------------------------------------------------------------------
// Mock — activo hasta que Alan complete Tarea 9.1 (backend de caja)
// ---------------------------------------------------------------------------

class CashRepositoryMock implements CashRepository {
  static const _fakeDelay = Duration(milliseconds: 500);

  /// Fondo inicial fijo de la sesión simulada — no existe todavía una UI de
  /// apertura real (fuera de alcance de la Tarea 9.2, ver plan aprobado).
  /// Mismo valor usado en el ejemplo de `docs/api/cash.yaml`.
  static const defaultOpeningAmountMxn = 500.0;

  static int _sessionCounter = 0;
  static int _movementCounter = 0;

  /// Movimientos de caja menor por sesión — vive en memoria mientras Alan no
  /// entregue `cash_movements` (Tarea 10.1). Clave: `CashSession.id`.
  static final Map<String, List<CashMovement>> _movementsBySession = {};

  /// Acceso síncrono usado por `_computeExpectedCashMxn` (mismo motivo que
  /// `SalesRepositoryMock.todaysSales`: evita el ciclo de dependencias de
  /// Riverpod descrito en `cash_session_provider.dart`) y por
  /// `CashMovementsNotifier.build()`.
  static List<CashMovement> movementsFor(String sessionId) =>
      List.unmodifiable(_movementsBySession[sessionId] ?? const []);

  @override
  Future<CashSession> openSession({
    required String cashierName,
    required double openingAmountMxn,
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

    // Inserta al inicio — misma convención que `CloseSessionWizard._addEntry`:
    // el movimiento recién registrado aparece primero como señal visual de
    // que la acción tuvo efecto.
    final list = _movementsBySession.putIfAbsent(sessionId, () => []);
    list.insert(0, movement);

    return movement;
  }
}
