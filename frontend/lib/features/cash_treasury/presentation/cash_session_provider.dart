import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_provider.dart';
import '../../sales_pos/domain/payment_entry.dart';
import '../data/cash_repository.dart';
import '../domain/banxico_denomination.dart';
import '../domain/cash_movement.dart';
import '../domain/cash_session.dart';

final cashRepositoryProvider = Provider<CashRepository>(
  (ref) => CashRepositoryImpl(
    client: ref.watch(dioClientProvider),
  ),
);

/// En qué está la pantalla de Caja (Integración de Caja, Oct 2026). Antes
/// sólo existía el turno y un `null` significaba "cargando" para siempre si
/// abrir fallaba — ahora un error se dice y se reintenta (CA-C1).
class CashLoad {
  const CashLoad._(this.loading, this.error);
  const CashLoad.loading() : this._(true, null);
  const CashLoad.ready() : this._(false, null);
  const CashLoad.failed(String message) : this._(false, message);

  final bool loading;
  final String? error;
}

final cashLoadProvider = StateProvider<CashLoad>((_) => const CashLoad.loading());

/// El turno abierto según el servidor, leído al momento de cobrar (V2/V3: si
/// alcanza el cambio, si hay turno). Fresco cada vez; un error se trata como
/// "no se sabe" y el cobro sigue sin avisos.
final cashShiftForCheckoutProvider = FutureProvider.autoDispose<CashSession?>(
  (ref) => ref.watch(cashRepositoryProvider).getActiveSession(),
);

// ---------------------------------------------------------------------------
// Notifier — sesión de caja activa (null = sin turno abierto)
// ---------------------------------------------------------------------------

class CashSessionNotifier extends Notifier<CashSession?> {
  @override
  CashSession? build() => null;

  CashRepository get _repo => ref.read(cashRepositoryProvider);

  void _setLoad(CashLoad load) => ref.read(cashLoadProvider.notifier).state = load;

  /// Pregunta al servidor si hay un turno abierto y lo retoma (A1). Sin turno,
  /// la pantalla ofrece abrirlo; un error se dice con "Reintentar".
  Future<void> load() async {
    _setLoad(const CashLoad.loading());
    try {
      state = await _repo.getActiveSession();
      _setLoad(const CashLoad.ready());
    } on CashException catch (e) {
      _setLoad(CashLoad.failed(e.message));
    } catch (_) {
      _setLoad(const CashLoad.failed('No pudimos consultar tu turno de caja.'));
    }
  }

  /// Vuelve a leer el turno sin mostrar carga (tras un movimiento, al volver a
  /// Caja, al deslizar hacia abajo). Si falla, se queda lo que había.
  Future<void> refresh() async {
    try {
      final fresh = await _repo.getActiveSession();
      if (fresh == null || state == null || fresh.id == state!.id) state = fresh;
    } catch (_) {}
  }

  /// Abre el turno con el fondo que declara el cajero (C1). Si el servidor dice
  /// que ya hay uno abierto, se retoma en vez de mostrar el error.
  Future<void> openSession(double openingAmountMxn) async {
    final cashierName = ref.read(currentUserNameProvider) ?? 'Cajero';
    try {
      state = await _repo.openSession(cashierName: cashierName, openingAmountMxn: openingAmountMxn);
      _setLoad(const CashLoad.ready());
    } on CashSessionAlreadyOpen {
      await load();
    }
  }

  /// Cierra el turno con el conteo físico capturado en el wizard. El esperado
  /// y el resultado los calcula el servidor (A2–A4).
  ///
  /// [movements] se conserva en la firma por compatibilidad con
  /// `CloseSessionWizard`; el servidor ya los conoce.
  Future<CashSession> closeSession(
    BanxicoCount physicalDenominations, {
    required List<CashMovement> movements,
  }) async {
    final current = state;
    if (current == null) {
      throw Exception('No hay una sesión de caja activa que cerrar.');
    }
    final closed = await _repo.closeSession(
      session: current,
      physicalDenominations: physicalDenominations,
    );
    state = closed;
    return closed;
  }

  /// Tras un cierre: sin turno; la pantalla ofrece abrir uno nuevo con su fondo.
  void startNewSession() {
    state = null;
    _setLoad(const CashLoad.ready());
  }
}

final cashSessionProvider = NotifierProvider<CashSessionNotifier, CashSession?>(
  CashSessionNotifier.new,
);

// ---------------------------------------------------------------------------
// Notifier — movimientos de caja menor del turno activo (Tarea 10.2.2)
// ---------------------------------------------------------------------------

class CashMovementsNotifier extends Notifier<List<CashMovement>> {
  /// Evita pisar la lista con una recarga vieja si el turno ya cambió antes
  /// de que la petición anterior contestara (mismo criterio que
  /// `SalesKardexNotifier._mounted`).
  String? _sessionIdInFlight;

  @override
  List<CashMovement> build() {
    // `.select` a propósito: sólo el *id* de sesión importa para decidir si
    // hay que recargar movimientos — `cerrar turno` cambia el `status` del
    // mismo `CashSession` (mismo id) y, sin este `select`, cada cierre
    // relanzaría `listMovements()` innecesariamente (y en tests, con
    // `startNewSession()` encadenado justo después, puede dejar un timer de
    // esa recarga huérfana pendiente al desmontar el árbol de widgets).
    final sessionId = ref.watch(cashSessionProvider.select((s) => s?.id));
    if (sessionId == null) return const [];
    Future.microtask(() => _reload(sessionId));
    return const [];
  }

  CashRepository get _repo => ref.read(cashRepositoryProvider);

  Future<void> _reload(String sessionId) async {
    _sessionIdInFlight = sessionId;
    try {
      final movements = await _repo.listMovements(sessionId);
      if (_sessionIdInFlight != sessionId) return;
      state = movements;
    } catch (_) {
      // La sección de movimientos simplemente queda vacía; no hay un lugar
      // dedicado en esta pantalla para un banner de error de esta lista.
    }
  }

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
      // El disponible es el esperado del servidor (ventas netas de cambio + movimientos);
      // el servidor vuelve a validarlo (422 INSUFFICIENT_CASH_FOR_WITHDRAWAL)
      final available = session.expectedCashMxn;
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
    // El esperado cambia: se relee del servidor (no recalcula nada aquí)
    await ref.read(cashSessionProvider.notifier).refresh();
  }
}

final cashMovementsProvider =
    NotifierProvider<CashMovementsNotifier, List<CashMovement>>(
  CashMovementsNotifier.new,
);

// ---------------------------------------------------------------------------
// Providers derivados — del resumen del servidor (Integración de Caja, Oct 2026)
// ---------------------------------------------------------------------------
//
// Antes se recalculaban con `GET /sales` del día filtrado por *nombre* de
// cajero y sumando lo entregado sin restar el cambio (A3, A4). Ahora el
// servidor manda: `GET /cash/active-session` trae el esperado y el desglose.

/// Efectivo esperado en vivo: fondo + ventas en efectivo netas de cambio +
/// entradas − retiros, según el servidor.
final expectedCashMxnProvider = FutureProvider<double>((ref) async {
  final session = ref.watch(cashSessionProvider);
  return session?.expectedCashMxn ?? 0;
});

/// Totales de pagos digitales del turno (SPEI/TPV/CoDi/Otro), informativos
/// para el Paso 2 del wizard — Subtarea 9.2.3.
final digitalPaymentTotalsProvider =
    FutureProvider<Map<PaymentMethodMxn, double>>((ref) async {
  final summary = ref.watch(cashSessionProvider)?.summary;
  if (summary == null) return {};
  return {
    for (final method in PaymentMethodMxn.values)
      if ((summary.digitalTotalsMxn[method.apiValue] ?? 0) > 0)
        method: summary.digitalTotalsMxn[method.apiValue]!,
  };
});
