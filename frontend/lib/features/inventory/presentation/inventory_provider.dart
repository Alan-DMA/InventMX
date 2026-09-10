import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/inventory_repository.dart';
import '../domain/product.dart';

// ---------------------------------------------------------------------------
// Estado
// ---------------------------------------------------------------------------

class InventoryState {
  const InventoryState({
    this.products = const [],
    this.query = '',
    this.activeCategory,
    this.showLowStock = false,
    this.currentPage = 1,
    this.totalPages = 1,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<Product> products;
  final String query;
  final String? activeCategory;
  final bool showLowStock;
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  bool get hasMorePages => currentPage < totalPages;
  bool get hasProducts => products.isNotEmpty;
  bool get hasError => error != null;

  /// Categorías únicas derivadas de los productos cargados.
  List<String> get availableCategories {
    final cats = products.map((p) => p.category).toSet().toList()..sort();
    return cats;
  }

  /// copyWith con sentinel para campos nullable (activeCategory, error).
  /// Los booleanos y primitivos se pasan directamente.
  InventoryState copyWith({
    List<Product>? products,
    String? query,
    // Sentinel: usar _keep para no cambiar el valor actual
    Object? activeCategory = _keep,
    bool? showLowStock,
    int? currentPage,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _keep,
  }) {
    return InventoryState(
      products: products ?? this.products,
      query: query ?? this.query,
      activeCategory: identical(activeCategory, _keep)
          ? this.activeCategory
          : activeCategory as String?,
      showLowStock: showLowStock ?? this.showLowStock,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }
}

/// Sentinel para distinguir "no se pasó el argumento" de "se pasó null".
const Object _keep = Object();

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class InventoryNotifier extends Notifier<InventoryState> {
  @override
  InventoryState build() {
    // Carga inicial al montar el provider
    Future.microtask(() => _load(resetList: true));
    return const InventoryState(isLoading: true);
  }

  InventoryRepository get _repo => ref.read(inventoryRepositoryProvider);

  // ── Debounce para búsqueda ──────────────────────────────────────────────
  Timer? _debounce;

  // ── Carga principal ─────────────────────────────────────────────────────

  Future<void> _load({required bool resetList}) async {
    if (resetList) {
      state = state.copyWith(isLoading: true, error: null);
    } else {
      state = state.copyWith(isLoadingMore: true);
    }

    try {
      final result = await _repo.getProducts(
        query: state.query.isEmpty ? null : state.query,
        category: state.activeCategory,
        lowStock: state.showLowStock,
        page: resetList ? 1 : state.currentPage,
        pageSize: 20,
      );

      final newProducts =
          resetList ? result.items : [...state.products, ...result.items];

      state = state.copyWith(
        products: newProducts,
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

  // ── API pública del notifier ─────────────────────────────────────────────

  /// Actualiza el texto de búsqueda con debounce de 300 ms.
  void setQuery(String value) {
    _debounce?.cancel();
    state = state.copyWith(query: value, currentPage: 1);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _load(resetList: true);
    });
  }

  /// Selecciona o deselecciona una categoría.
  /// Pasar null limpia el filtro (→ "Todos").
  void setCategory(String? category) {
    state = state.copyWith(
      activeCategory: category,
      currentPage: 1,
    );
    _load(resetList: true);
  }

  /// Alterna el filtro de stock bajo.
  void toggleLowStock() {
    state = state.copyWith(
      showLowStock: !state.showLowStock,
      currentPage: 1,
    );
    _load(resetList: true);
  }

  /// Carga la siguiente página (llamado al llegar al 80% del scroll).
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMorePages) return;
    state = state.copyWith(currentPage: state.currentPage + 1);
    await _load(resetList: false);
  }

  /// Reintenta la carga tras un error.
  Future<void> retry() async {
    state = state.copyWith(
      error: null,
      currentPage: 1,
    );
    await _load(resetList: true);
  }

  /// Crea un producto nuevo con los 3 campos vitales y lo inserta
  /// al inicio de la lista sin necesidad de recargar desde el servidor.
  /// Lanza excepción si el API devuelve error (la captura el modal).
  Future<Product> addProduct({
    required String name,
    required double priceMxn,
    int stock = 0,
  }) async {
    final product = await _repo.createProduct(
      name: name,
      priceMxn: priceMxn,
      stock: stock,
    );
    // Inserta al inicio para que sea inmediatamente visible
    state = state.copyWith(products: [product, ...state.products]);
    return product;
  }

  /// Ajusta el stock de un producto y actualiza su estado local.
  /// direction: +1 para entrada, -1 para salida/merma.
  Future<void> adjustStock({
    required String productId,
    required String movementType,
    required int quantity,
    required String reason,
  }) async {
    await _repo.adjustStock(
      productId: productId,
      movementType: movementType,
      quantity: quantity,
      reason: reason,
    );
    // Actualiza el available_stock localmente según la dirección
    final isIn = movementType == 'MANUAL_ADJUSTMENT_IN';
    final delta = isIn ? quantity : -quantity;
    _patchProductStock(productId, delta);
  }

  /// Traslada stock entre almacenes y actualiza el estado local.
  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required int quantity,
    String? notes,
  }) async {
    await _repo.transferStock(
      productId: productId,
      fromWarehouseId: fromWarehouseId,
      toWarehouseId: toWarehouseId,
      quantity: quantity,
      notes: notes,
    );
    // En MVP mono-almacén el stock total no cambia; el provider
    // refresca el producto para reflejar el cambio de almacén.
    // Cuando el backend soporte multi-almacén correctamente,
    // este método recibirá el producto actualizado en la respuesta.
  }

  /// Actualiza los campos editables de un producto vía PATCH /inventory/products/{id}.
  /// Retorna el producto actualizado y lo reemplaza en la lista en memoria.
  /// Lanza excepción si el API devuelve error (la captura EditProductScreen).
  Future<Product> updateProduct({
    required String productId,
    String? name,
    double? priceMxn,
    double? costMxn,
    String? category,
    String? barcode,
    int? minStockAlert,
    String? imageUrl,
    bool? isActive,
  }) async {
    final updated = await _repo.updateProduct(
      productId: productId,
      name: name,
      priceMxn: priceMxn,
      costMxn: costMxn,
      category: category,
      barcode: barcode,
      minStockAlert: minStockAlert,
      imageUrl: imageUrl,
      isActive: isActive,
    );
    // Reemplaza el producto en la lista local sin recargar todo el inventario
    state = state.copyWith(
      products:
          state.products.map((p) => p.id == productId ? updated : p).toList(),
    );
    return updated;
  }

  /// Actualiza available_stock de un producto en la lista en memoria.
  void _patchProductStock(String productId, int delta) {
    final updated = state.products.map((p) {
      if (p.id != productId) return p;
      final newAvailable = (p.availableStock + delta).clamp(0, 999999);
      return p.copyWith(
        stock: p.stock + delta,
        availableStock: newAvailable,
      );
    }).toList();
    state = state.copyWith(products: updated);
  }

  void cancelDebounce() {
    _debounce?.cancel();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final inventoryProvider = NotifierProvider<InventoryNotifier, InventoryState>(
  InventoryNotifier.new,
);

/// FutureProvider.family para el detalle de un producto individual.
///
/// Estrategia: caché primero (si el producto ya está en inventoryProvider
/// no lanza una petición adicional), fallback a getProductById cuando no
/// está en memoria (acceso directo por URL o lista vacía).
final productDetailProvider =
    FutureProvider.family<Product, String>((ref, id) async {
  // Intenta obtener desde la lista ya cargada en memoria
  final cached = ref
      .watch(inventoryProvider)
      .products
      .where((p) => p.id == id)
      .firstOrNull;

  if (cached != null) return cached;

  // Fallback: petición directa al repositorio
  return ref.read(inventoryRepositoryProvider).getProductById(id);
});

/// Expone las categorías únicas ya cargadas en el inventario.
/// Usado por EditProductScreen para los chips de sugerencia.
final availableCategoriesProvider = Provider<List<String>>((ref) {
  return ref.watch(inventoryProvider).availableCategories;
});
