import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/sales_repository.dart';
import '../domain/sale_summary.dart';

// ---------------------------------------------------------------------------
// Estado
// ---------------------------------------------------------------------------

/// Estado del kardex de ventas (Fase 2). Misma anatomía que `KardexState`
/// del inventario (4.2.B): lista acumulada + página actual + filtros.
///
/// `total` y `totalAmountMxn` son del **recorte completo**, no de la página:
/// alimentan el resumen "N ventas · $X" que acompaña a los filtros.
class SalesKardexState {
  const SalesKardexState({
    this.sales = const [],
    this.query = const SalesQuery(),
    this.cashiers = const [],
    this.total = 0,
    this.totalAmountMxn = 0,
    this.currentPage = 1,
    this.totalPages = 1,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<SaleSummary> sales;
  final SalesQuery query;

  /// Opciones del filtro por cajero (se cargan una vez).
  final List<String> cashiers;
  final int total;
  final double totalAmountMxn;
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  bool get hasMore => currentPage < totalPages;
  bool get hasSales => sales.isNotEmpty;
  bool get hasError => error != null;
  bool get hasActiveFilters => !query.isEmpty;

  SalesKardexState copyWith({
    List<SaleSummary>? sales,
    SalesQuery? query,
    List<String>? cashiers,
    int? total,
    double? totalAmountMxn,
    int? currentPage,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _keep,
  }) {
    return SalesKardexState(
      sales: sales ?? this.sales,
      query: query ?? this.query,
      cashiers: cashiers ?? this.cashiers,
      total: total ?? this.total,
      totalAmountMxn: totalAmountMxn ?? this.totalAmountMxn,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }
}

const Object _keep = Object();

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// `autoDispose` a propósito: mientras la pantalla del kardex esté en el
/// stack (debajo del detalle) el estado y el scroll sobreviven; al salir se
/// libera, y la siguiente apertura trae las ventas cobradas entre tanto.
class SalesKardexNotifier extends AutoDisposeNotifier<SalesKardexState> {
  static const _pageSize = 20;

  /// Las cargas son asíncronas y el provider es `autoDispose`: si el usuario
  /// sale antes de que responda el repositorio, no hay estado que actualizar.
  bool _mounted = true;

  @override
  SalesKardexState build() {
    _mounted = true;
    ref.onDispose(() => _mounted = false);
    Future.microtask(_initialLoad);
    return const SalesKardexState(isLoading: true);
  }

  SalesRepository get _repo => ref.read(salesRepositoryProvider);

  Future<void> _initialLoad() async {
    // Las opciones de cajero no dependen del filtro: se piden una sola vez.
    try {
      final cashiers = await _repo.getCashiers();
      if (!_mounted) return;
      state = state.copyWith(cashiers: cashiers);
    } catch (_) {
      // El filtro por cajero simplemente no ofrece opciones.
    }
    if (!_mounted) return;
    await _load(query: state.query, resetList: true);
  }

  /// [silent] recarga sin pasar por el skeleton (pull-to-refresh): la lista
  /// vieja se queda a la vista hasta que llega la nueva.
  Future<void> _load({
    required SalesQuery query,
    required bool resetList,
    bool silent = false,
  }) async {
    if (resetList) {
      state = state.copyWith(isLoading: !silent, error: null, query: query);
    } else {
      state = state.copyWith(isLoadingMore: true);
    }

    try {
      final result = await _repo.getSales(
        query: query,
        page: resetList ? 1 : state.currentPage,
        pageSize: _pageSize,
      );
      // Si el filtro cambió mientras esperábamos, esta respuesta ya no aplica.
      if (!_mounted || state.query != query) return;

      state = state.copyWith(
        sales: resetList ? result.items : [...state.sales, ...result.items],
        total: result.total,
        totalAmountMxn: result.totalAmountMxn,
        currentPage: result.page,
        totalPages: result.totalPages,
        isLoading: false,
        isLoadingMore: false,
        error: null,
      );
    } catch (e) {
      if (!_mounted) return;
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: e.toString(),
      );
    }
  }

  // ── API pública ────────────────────────────────────────────────────────

  /// Siguiente página (scroll infinito al 80 % de la lista).
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(currentPage: state.currentPage + 1);
    await _load(query: state.query, resetList: false);
  }

  Future<void> setDateFrom(DateTime? date) =>
      _load(query: state.query.copyWith(dateFrom: date), resetList: true);

  Future<void> setDateTo(DateTime? date) =>
      _load(query: state.query.copyWith(dateTo: date), resetList: true);

  Future<void> setPaymentKind(SalePaymentKind? kind) =>
      _load(query: state.query.copyWith(paymentKind: kind), resetList: true);

  Future<void> setCashier(String? name) =>
      _load(query: state.query.copyWith(cashierName: name), resetList: true);

  Future<void> clearFilters() =>
      _load(query: const SalesQuery(), resetList: true);

  /// Pull-to-refresh: recarga desde la primera página con el mismo filtro,
  /// sin vaciar la lista mientras tanto.
  Future<void> refresh() =>
      _load(query: state.query, resetList: true, silent: true);

  /// Tras un error sí se muestra el skeleton: no hay lista que conservar.
  Future<void> retry() => _load(query: state.query, resetList: true);
}

final salesKardexProvider =
    NotifierProvider.autoDispose<SalesKardexNotifier, SalesKardexState>(
  SalesKardexNotifier.new,
);

// ---------------------------------------------------------------------------
// Detalle
// ---------------------------------------------------------------------------

/// `GET /sales/{id}` para la pantalla de consulta del ticket.
final saleDetailProvider = FutureProvider.autoDispose.family(
  (ref, String id) => ref.watch(salesRepositoryProvider).getSaleById(id),
);
