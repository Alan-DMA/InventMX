import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/login_provider.dart';
import '../../sales_pos/data/sales_repository.dart';
import '../../sales_pos/domain/payment_entry.dart';
import '../data/cash_repository.dart';
import '../domain/banxico_denomination.dart';
import '../domain/cash_movement.dart';
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
// Notifier — movimientos de caja menor del turno activo (Tarea 10.2.2)
// ---------------------------------------------------------------------------

class CashMovementsNotifier extends Notifier<List<CashMovement>> {
  @override
  List<CashMovement> build() {
    // Recalcula automáticamente al abrir un turno nuevo (`startNewSession`)
    // — la sesión cambia de id y el `build()` vuelve a leer del store Mock,
    // que empieza vacío para el nuevo id.
    final session = ref.watch(cashSessionProvider);
    if (session == null) return const [];
    return CashRepositoryMock.movementsFor(session.id);
  }

  CashRepository get _repo => ref.read(cashRepositoryProvider);

  /// Registra un retiro o entrada de caja menor del turno activo.
  ///
  /// Un retiro que exceda el efectivo actualmente disponible se rechaza
  /// antes de llamar al repositorio — replica el `422
  /// INSUFFICIENT_CASH_FOR_WITHDRAWAL` de `docs/api/cash.yaml`.
  Future<void> addMovement({
    required CashMovementType type,
    required double amountMxn,
    required String description,
  }) async {
    final session = ref.read(cashSessionProvider);
    if (session == null) {
      throw Exception('No hay una sesión de caja activa.');
    }

    if (type == CashMovementType.withdrawal) {
      // Lee `_computeExpectedCashMxn` directamente (no `ref.read
      // (expectedCashMxnProvider)`): ese provider observa
      // `cashMovementsProvider` para invalidarse, así que leerlo desde el
      // propio notifier de `cashMovementsProvider` formaría un ciclo que
      // Riverpod rechaza en tiempo de ejecución (`CircularDependencyError`).
      final available = _computeExpectedCashMxn(session);
      if (amountMxn > available) {
        throw Exception(
          'Retiro de \$${amountMxn.toStringAsFixed(2)} MXN excede el '
          'efectivo disponible en caja (\$${available.toStringAsFixed(2)} MXN).',
        );
      }
    }

    final movement = await _repo.addMovement(
      sessionId: session.id,
      type: type,
      amountMxn: amountMxn,
      description: description,
    );

    // El movimiento tocado aparece primero — misma convención UX que
    // `CloseSessionWizard._addEntry` (Tarea 9.2).
    state = [movement, ...state];
  }
}

final cashMovementsProvider =
    NotifierProvider<CashMovementsNotifier, List<CashMovement>>(
  CashMovementsNotifier.new,
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

  // Fórmula de conciliación (Doc. Maestro, Subtarea 10.1.1):
  // Fondo Inicial + Ventas Efectivo − Retiros + Entradas.
  final movementsNet = CashRepositoryMock.movementsFor(session.id).fold<double>(
        0.0,
        (sum, m) => sum +
            (m.type == CashMovementType.deposit ? m.amountMxn : -m.amountMxn),
      );

  return session.openingAmountMxn + cashFromSales + movementsNet;
}

final expectedCashMxnProvider = Provider<double>((ref) {
  final session = ref.watch(cashSessionProvider);
  if (session == null) return 0;
  // Se observa (sin usar el valor) solo para invalidar este provider cuando
  // se registra un movimiento — `_computeExpectedCashMxn` sigue leyendo el
  // store Mock directamente para evitar el ciclo de dependencias explicado
  // arriba.
  ref.watch(cashMovementsProvider);
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
