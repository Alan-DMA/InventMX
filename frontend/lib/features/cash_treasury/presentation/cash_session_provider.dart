import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/login_provider.dart';
import '../../sales_pos/data/sales_repository.dart';
import '../../sales_pos/domain/payment_entry.dart';
import '../data/cash_repository.dart';
import '../domain/banxico_denomination.dart';
import '../domain/cash_session.dart';

final cashRepositoryProvider = Provider<CashRepository>(
  (_) => CashRepositoryMock(),
);

// ---------------------------------------------------------------------------
// Notifier — sesión de caja activa (null si aún no se ha abierto ninguna)
// ---------------------------------------------------------------------------

class CashSessionNotifier extends Notifier<CashSession?> {
  @override
  CashSession? build() => null;

  CashRepository get _repo => ref.read(cashRepositoryProvider);

  /// Abre una sesión Mock si no hay ninguna activa. No existe todavía una UI
  /// de apertura real (fuera de alcance de la Tarea 9.2) — se usa un fondo
  /// inicial fijo mientras Alan no entregue `POST /cash/open-session`.
  Future<void> ensureOpenSession() async {
    if (state != null && state!.status == CashSessionStatus.open) return;

    final cashierName = ref.read(currentUserNameProvider) ?? 'Cajero';
    state = await _repo.openSession(
      cashierName: cashierName,
      openingAmountMxn: CashRepositoryMock.defaultOpeningAmountMxn,
    );
  }

  /// Cierra el turno con el conteo físico capturado en el wizard.
  Future<CashSession> closeSession(BanxicoCount physicalDenominations) async {
    final current = state;
    if (current == null) {
      throw Exception('No hay una sesión de caja activa que cerrar.');
    }

    final updated = current.copyWith(
      expectedCashMxn: _computeExpectedCashMxn(current),
    );
    final closed = await _repo.closeSession(
      session: updated,
      physicalDenominations: physicalDenominations,
    );
    state = closed;
    return closed;
  }

  /// Abre un turno nuevo — permite seguir probando el flujo tras un cierre
  /// (la sesión Mock vive solo en memoria, ver `SalesRepositoryMock`).
  Future<void> startNewSession() async {
    state = null;
    await ensureOpenSession();
  }
}

final cashSessionProvider = NotifierProvider<CashSessionNotifier, CashSession?>(
  CashSessionNotifier.new,
);

// ---------------------------------------------------------------------------
// Providers derivados — recalculados a partir de las ventas del turno
// (mismo dataset que ya alimenta el tablero de comisiones, Tarea 8.2.3)
// ---------------------------------------------------------------------------

/// Efectivo esperado en vivo: fondo inicial + ventas en efectivo desde la
/// apertura del turno.
///
/// Función pura (no un `Provider.read` sobre otro provider) a propósito:
/// `CashSessionNotifier.closeSession()` necesita este mismo cálculo y
/// leerlo vía `expectedCashMxnProvider` (que a su vez observa
/// `cashSessionProvider`) forma un ciclo que Riverpod rechaza en tiempo de
/// ejecución (`CircularDependencyError`).
double _computeExpectedCashMxn(CashSession session) {
  final cashFromSales = SalesRepositoryMock.todaysSales
      .where((sale) => sale.completedAt.isAfter(session.openedAt))
      .expand((sale) => sale.payments)
      .where((payment) => payment.method == PaymentMethodMxn.cashMxn)
      .fold(0.0, (sum, payment) => sum + payment.amountMxn);

  return session.openingAmountMxn + cashFromSales;
}

final expectedCashMxnProvider = Provider<double>((ref) {
  final session = ref.watch(cashSessionProvider);
  if (session == null) return 0;
  return _computeExpectedCashMxn(session);
});

/// Totales de pagos digitales del turno (SPEI/TPV/CoDi/Otro), informativos
/// para el Paso 2 del wizard — Subtarea 9.2.3.
final digitalPaymentTotalsProvider = Provider<Map<PaymentMethodMxn, double>>((ref) {
  final session = ref.watch(cashSessionProvider);
  if (session == null) return {};

  final totals = <PaymentMethodMxn, double>{};
  final salesInShift = SalesRepositoryMock.todaysSales
      .where((sale) => sale.completedAt.isAfter(session.openedAt));

  for (final sale in salesInShift) {
    for (final payment in sale.payments) {
      if (payment.method == PaymentMethodMxn.cashMxn) continue;
      totals[payment.method] = (totals[payment.method] ?? 0) + payment.amountMxn;
    }
  }
  return totals;
});
