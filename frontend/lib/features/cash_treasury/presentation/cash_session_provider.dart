import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_provider.dart';
import '../../sales_pos/data/sales_repository.dart';
import '../../sales_pos/domain/payment_entry.dart';
import '../../sales_pos/domain/sale_summary.dart';
import '../data/cash_repository.dart';
import '../domain/banxico_denomination.dart';
import '../domain/cash_movement.dart';
import '../domain/cash_session.dart';

final cashRepositoryProvider = Provider<CashRepository>(
  (ref) => CashRepositoryImpl(
    client: ref.watch(dioClientProvider),
  ),
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
  ///
  /// [movements] lo trae quien llama (`ref.read(cashMovementsProvider)` en
  /// `CloseSessionWizard`) en vez de leerlo aquí adentro: `cashMovementsProvider`
  /// depende de `cashSessionProvider`, y este método vive en el notifier
  /// *dueño* de `cashSessionProvider` — Riverpod marca eso como dependencia
  /// circular aunque sea un `ref.read`, no un `ref.watch`. Mismo motivo por
  /// el que las ventas se piden frescas y directas (`_fetchShiftSalesRaw`)
  /// en vez de vía `_shiftSalesProvider`.
  Future<CashSession> closeSession(
    BanxicoCount physicalDenominations, {
    required List<CashMovement> movements,
  }) async {
    final current = state;
    if (current == null) {
      throw Exception('No hay una sesión de caja activa que cerrar.');
    }

    final sales = await _fetchShiftSalesRaw(ref.read(salesRepositoryProvider), current);
    final updated = current.copyWith(
      expectedCashMxn: _sumExpectedCashMxn(current, sales, movements),
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
      // `state` (no `ref.read(cashMovementsProvider)`): son el mismo valor
      // dentro de este notifier, pero usar `state` deja claro que es el
      // disponible *antes* de este movimiento, sin depender de un `ref.read`
      // sobre el propio provider que este método está mutando.
      final sales = await ref.read(_shiftSalesProvider.future);
      final available = _sumExpectedCashMxn(session, sales, state);
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
// Providers derivados — recalculados a partir de las ventas reales del turno
// ---------------------------------------------------------------------------

/// Trae todas las ventas del comercio desde la apertura del turno, paginando
/// hasta agotar `total` — un turno normal cabe en una o dos páginas.
///
/// Filtra por cajero **en cliente** (no vía `SalesQuery.cashierName`):
/// ese filtro del repositorio resuelve el nombre contra `GET /users`, que
/// exige `settings.manage_users` — un Cajero cerrando su propio turno no
/// necesariamente lo tiene, y este cálculo debe funcionarle siempre.
Future<List<SaleSummary>> _fetchShiftSalesRaw(
  SalesRepository salesRepo,
  CashSession session,
) async {
  final sales = <SaleSummary>[];
  var page = 1;
  const pageSize = 100;
  while (true) {
    final result = await salesRepo.getSales(
      query: SalesQuery(dateFrom: session.openedAt),
      page: page,
      pageSize: pageSize,
    );
    sales.addAll(result.items);
    if (sales.length >= result.total || result.items.isEmpty) break;
    page++;
  }
  return sales.where((s) => s.cashierName == session.cashierName).toList();
}

/// Cacheado por sesión (Sep 2026): sólo depende de `cashSessionProvider`, no
/// de `cashMovementsProvider` — un retiro/entrada de caja menor no cambia
/// qué se vendió, así que registrar un movimiento no debe volver a pedir
/// `GET /sales` completo.
///
/// `CashSessionNotifier.closeSession()` no puede leer este provider (llama a
/// `_fetchShiftSalesRaw` directo): siendo el notifier dueño de
/// `cashSessionProvider`, del que este depende, Riverpod lo marca como
/// dependencia circular incluso vía `ref.read`.
final _shiftSalesProvider = FutureProvider<List<SaleSummary>>((ref) async {
  final session = ref.watch(cashSessionProvider);
  if (session == null) return const [];
  return _fetchShiftSalesRaw(ref.read(salesRepositoryProvider), session);
});

/// Fórmula de conciliación (Doc. Maestro, Subtarea 10.1.1):
/// Fondo Inicial + Ventas Efectivo − Retiros + Entradas.
///
/// Función pura y síncrona a propósito — `sales` y `movements` ya resueltos
/// (Sep 2026: antes esta función volvía a pedir `GET /sales` y
/// `GET /cash/sessions/{id}/movements` en cada llamada, incluso cuando
/// `movements` ya vivía en memoria vía `cashMovementsProvider`).
double _sumExpectedCashMxn(
  CashSession session,
  List<SaleSummary> sales,
  List<CashMovement> movements,
) {
  final cashFromSales = sales
      .expand((sale) => sale.payments)
      .where((payment) => payment.method == PaymentMethodMxn.cashMxn)
      .fold(0.0, (sum, payment) => sum + payment.amountMxn);

  final movementsNet = movements.fold<double>(
    0.0,
    (sum, m) =>
        sum + (m.type == CashMovementType.deposit ? m.amountMxn : -m.amountMxn),
  );

  return session.openingAmountMxn + cashFromSales + movementsNet;
}

/// Efectivo esperado en vivo (Sep 2026 — antes leía
/// `SalesRepositoryMock.todaysSales`/`CashRepositoryMock.movementsFor`
/// estático, ajeno a los repositorios inyectados).
final expectedCashMxnProvider = FutureProvider<double>((ref) async {
  final session = ref.watch(cashSessionProvider);
  if (session == null) return 0;
  final sales = await ref.watch(_shiftSalesProvider.future);
  final movements = ref.watch(cashMovementsProvider);
  return _sumExpectedCashMxn(session, sales, movements);
});

/// Totales de pagos digitales del turno (SPEI/TPV/CoDi/Otro), informativos
/// para el Paso 2 del wizard — Subtarea 9.2.3.
final digitalPaymentTotalsProvider =
    FutureProvider<Map<PaymentMethodMxn, double>>((ref) async {
  final session = ref.watch(cashSessionProvider);
  if (session == null) return {};

  final sales = await ref.watch(_shiftSalesProvider.future);

  final totals = <PaymentMethodMxn, double>{};
  for (final sale in sales) {
    for (final payment in sale.payments) {
      if (payment.method == PaymentMethodMxn.cashMxn) continue;
      totals[payment.method] = (totals[payment.method] ?? 0) + payment.amountMxn;
    }
  }
  return totals;
});
