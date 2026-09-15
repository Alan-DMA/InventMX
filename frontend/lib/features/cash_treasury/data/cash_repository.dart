import '../domain/banxico_denomination.dart';
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
}
