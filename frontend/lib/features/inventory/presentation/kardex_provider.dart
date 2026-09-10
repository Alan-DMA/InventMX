import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory_movement.dart';

// ---------------------------------------------------------------------------
// Parámetros del provider (identificador único por producto + filtros)
// ---------------------------------------------------------------------------

class KardexParams {
  const KardexParams({
    required this.productId,
    this.movementType,
    this.dateFrom,
    this.dateTo,
  });

  final String productId;
  final String? movementType;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KardexParams &&
          other.productId == productId &&
          other.movementType == movementType &&
          other.dateFrom == dateFrom &&
          other.dateTo == dateTo);

  @override
  int get hashCode => Object.hash(productId, movementType, dateFrom, dateTo);

  KardexParams copyWith({
    String? movementType,
    Object? clearMovementType = _keep,
    DateTime? dateFrom,
    Object? clearDateFrom = _keep,
    DateTime? dateTo,
    Object? clearDateTo = _keep,
  }) {
    return KardexParams(
      productId: productId,
      movementType: identical(clearMovementType, _keep)
          ? (movementType ?? this.movementType)
          : null,
      dateFrom: identical(clearDateFrom, _keep)
          ? (dateFrom ?? this.dateFrom)
          : null,
      dateTo: identical(clearDateTo, _keep) ? (dateTo ?? this.dateTo) : null,
    );
  }
}

const Object _keep = Object();

// ---------------------------------------------------------------------------
// Estado
// ---------------------------------------------------------------------------

class KardexState {
  const KardexState({
    this.movements = const [],
    this.params = const KardexParams(productId: ''),
    this.currentPage = 1,
    this.totalPages = 1,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<InventoryMovement> movements;
  final KardexParams params;
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  bool get hasMore => currentPage < totalPages;
  bool get hasMovements => movements.isNotEmpty;
  bool get hasError => error != null;
  bool get hasActiveFilters =>
      params.movementType != null ||
      params.dateFrom != null ||
      params.dateTo != null;

  KardexState copyWith({
    List<InventoryMovement>? movements,
    KardexParams? params,
    int? currentPage,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _keep,
  }) {
    return KardexState(
      movements: movements ?? this.movements,
      params: params ?? this.params,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class KardexNotifier extends FamilyNotifier<KardexState, String> {
  @override
  KardexState build(String productId) {
    final params = KardexParams(productId: productId);
    Future.microtask(() => _load(params: params, resetList: true));
    return KardexState(
      params: params,
      isLoading: true,
    );
  }

  InventoryRepository get _repo => ref.read(inventoryRepositoryProvider);

  // ── Carga principal ─────────────────────────────────────────────────────

  Future<void> _load({
    required KardexParams params,
    required bool resetList,
  }) async {
    if (resetList) {
      state = state.copyWith(isLoading: true, error: null);
    } else {
      state = state.copyWith(isLoadingMore: true);
    }

    try {
      final result = await _repo.getMovements(
        productId: params.productId,
        movementType: params.movementType,
        dateFrom: params.dateFrom,
        dateTo: params.dateTo,
        page: resetList ? 1 : state.currentPage,
        pageSize: 20,
      );

      final newMovements = resetList
          ? result.items
          : [...state.movements, ...result.items];

      state = state.copyWith(
        movements: newMovements,
        params: params,
        currentPage: result.page,
        totalPages: result.totalPages,
        isLoading: false,
        isLoadingMore: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: e.toString(),
      );
    }
  }

  // ── API pública ──────────────────────────────────────────────────────────

  /// Carga la siguiente página (scroll infinito al 80% de la lista).
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(currentPage: state.currentPage + 1);
    await _load(params: state.params, resetList: false);
  }

  /// Aplica filtro por tipo de movimiento.
  Future<void> setMovementTypeFilter(String? type) async {
    final newParams = type == null
        ? state.params.copyWith(clearMovementType: null)
        : state.params.copyWith(movementType: type);
    await _load(params: newParams, resetList: true);
  }

  /// Aplica filtro por fecha de inicio.
  Future<void> setDateFrom(DateTime? date) async {
    final newParams = date == null
        ? state.params.copyWith(clearDateFrom: null)
        : state.params.copyWith(dateFrom: date);
    await _load(params: newParams, resetList: true);
  }

  /// Aplica filtro por fecha de fin.
  Future<void> setDateTo(DateTime? date) async {
    final newParams = date == null
        ? state.params.copyWith(clearDateTo: null)
        : state.params.copyWith(dateTo: date);
    await _load(params: newParams, resetList: true);
  }

  /// Limpia todos los filtros activos.
  Future<void> clearFilters() async {
    final cleanParams = KardexParams(productId: state.params.productId);
    await _load(params: cleanParams, resetList: true);
  }

  /// Reintenta la carga tras un error.
  Future<void> retry() async {
    state = state.copyWith(error: null, currentPage: 1);
    await _load(params: state.params, resetList: true);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final kardexProvider =
    NotifierProvider.family<KardexNotifier, KardexState, String>(
  KardexNotifier.new,
);
