import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../data/inventory_repository.dart';
import '../domain/product.dart';

// ---------------------------------------------------------------------------
// Modelos auxiliares para UI y selección
// ---------------------------------------------------------------------------

/// Modelo ligero para selección y visualización de almacenes
class WarehouseOption {
  const WarehouseOption({
    required this.id,
    required this.name,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final bool isDefault;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WarehouseOption && other.id == id && other.name == name);

  @override
  int get hashCode => Object.hash(id, name);
}

// ---------------------------------------------------------------------------
// Estado del Inventario
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

  /// Categorías únicas derivadas de los productos cargados
  List<String> get availableCategories {
    final cats = products.map((p) => p.category).toSet().toList()..sort();
    return cats;
  }

  /// copyWith con sentinel para campos nullable
  InventoryState copyWith({
    List<Product>? products,
    String? query,
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

/// Sentinel para distinguir "no se pasó el argumento" de "se pasó null"
const Object _keep = Object();

// ---------------------------------------------------------------------------
// Notifier del Catálogo de Inventario
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

  /// Actualiza el texto de búsqueda con debounce de 300 ms
  void setQuery(String value) {
    _debounce?.cancel();
    state = state.copyWith(query: value, currentPage: 1);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _load(resetList: true);
    });
  }

  /// Selecciona o deselecciona una categoría (null = "Todos")
  void setCategory(String? category) {
    state = state.copyWith(
      activeCategory: category,
      currentPage: 1,
    );
    _load(resetList: true);
  }

  /// Alterna el filtro de stock bajo
  void toggleLowStock() {
    state = state.copyWith(
      showLowStock: !state.showLowStock,
      currentPage: 1,
    );
    _load(resetList: true);
  }

  /// Fuerza el filtro de stock bajo a un valor concreto (a diferencia de
  /// [toggleLowStock]). Lo usa el Dashboard al entrar desde "Ver todo" en
  /// alertas: no puede alternar a ciegas sin saber en qué quedó el filtro.
  void setLowStock(bool value) {
    if (state.showLowStock == value) return;
    state = state.copyWith(
      showLowStock: value,
      currentPage: 1,
    );
    _load(resetList: true);
  }

  /// Carga la siguiente página para scroll infinito
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMorePages) return;
    state = state.copyWith(currentPage: state.currentPage + 1);
    await _load(resetList: false);
  }

  /// Reintenta la carga tras un error
  Future<void> retry() async {
    state = state.copyWith(
      error: null,
      currentPage: 1,
    );
    await _load(resetList: true);
  }

  /// Crea un producto nuevo con los 3 campos vitales (o extendidos) y lo inserta al inicio
  Future<Product> addProduct({
    required String name,
    required double priceMxn,
    int stock = 0,
    String? category,
    String? barcode,
    double? costMxn,
    int? minStockAlert,
    String? imageUrl,
  }) async {
    final product = await _repo.createProduct(
      name: name,
      priceMxn: priceMxn,
      stock: stock,
      category: category,
      barcode: barcode,
      costMxn: costMxn,
      minStockAlert: minStockAlert,
      imageUrl: imageUrl,
    );
    // Inserta al inicio para que sea inmediatamente visible en UI
    state = state.copyWith(products: [product, ...state.products]);
    return product;
  }

  /// Ajusta el stock de un producto y actualiza su estado local
  Future<void> adjustStock({
    required String productId,
    required String movementType,
    required int quantity,
    required String reason,
    String? warehouseId,
  }) async {
    await _repo.adjustStock(
      productId: productId,
      movementType: movementType,
      quantity: quantity,
      reason: reason,
      warehouseId: warehouseId,
    );
    final isIn = movementType == 'MANUAL_ADJUSTMENT_IN' ||
        movementType == 'ADJUSTMENT_IN' ||
        movementType == 'PURCHASE_ENTRY' ||
        movementType == 'PURCHASE_IN';
    final delta = isIn ? quantity : -quantity;
    _patchProductStock(productId, delta);
  }

  /// Traslada stock entre almacenes y actualiza el estado local
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
  }

  /// Actualiza los campos editables de un producto vía PUT /api/v1/inventory/products/{id}
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

  /// Actualiza available_stock de un producto en la lista en memoria
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

/// FutureProvider.family para el detalle de un producto individual
final productDetailProvider =
    FutureProvider.family<Product, String>((ref, id) async {
  final cached = ref
      .watch(inventoryProvider)
      .products
      .where((p) => p.id == id)
      .firstOrNull;

  if (cached != null) return cached;

  return ref.read(inventoryRepositoryProvider).getProductById(id);
});

/// Categorías cargadas dinámicamente desde el backend PostgreSQL
final categoriesProvider = FutureProvider<List<String>>((ref) async {
  final client = ref.watch(dioClientProvider);
  try {
    final response = await client.get('/api/v1/inventory/categories');
    final data = response.data;
    if (data is List && data.isNotEmpty) {
      final list = data
          .map((c) => (c is Map && c['name'] != null) ? c['name'].toString() : '')
          .where((name) => name.isNotEmpty)
          .toList();
      return list..sort();
    }
  } catch (_) {}
  return ref.watch(inventoryProvider).availableCategories;
});

/// Proveedor de almacenes del comercio
final warehousesProvider = FutureProvider<List<WarehouseOption>>((ref) async {
  final client = ref.watch(dioClientProvider);
  try {
    final response = await client.get('/api/v1/inventory/warehouses');
    final data = response.data;
    if (data is List && data.isNotEmpty) {
      return data.map((w) => WarehouseOption(
        id: (w['id'] ?? '').toString(),
        name: (w['name'] ?? 'Almacén').toString(),
        isDefault: w['is_default'] == true,
      )).toList();
    }
  } catch (_) {}
  return const [WarehouseOption(id: 'default', name: 'Almacén Principal', isDefault: true)];
});

/// Expone las categorías únicas ya cargadas en el inventario
final availableCategoriesProvider = Provider<List<String>>((ref) {
  final dynamicCats = ref.watch(categoriesProvider).valueOrNull;
  if (dynamicCats != null && dynamicCats.isNotEmpty) {
    return dynamicCats;
  }
  return ref.watch(inventoryProvider).availableCategories;
});
