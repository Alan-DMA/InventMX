import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/auth/presentation/login_provider.dart';
import '../../../features/inventory/domain/product.dart';
import '../data/sales_repository.dart';
import '../domain/cart_item.dart';
import '../domain/cart_state.dart';
import '../domain/payment_entry.dart';

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Gestiona el estado del carrito del POS y orquesta el checkout.
///
/// Trazabilidad: Constitución Art. I (1.2.8 Rapidez), Art. VII (7.3 Lazy Loading)
///              Doc. Maestro RF-09, SR-04 · HU-11 / CU-12
class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  SalesRepository get _repo => ref.read(salesRepositoryProvider);

  // ── Debounce para búsqueda ───────────────────────────────────────────────
  Timer? _searchDebounce;

  // ── Búsqueda ─────────────────────────────────────────────────────────────

  /// Actualiza la query de búsqueda con debounce de 300ms.
  void setSearchQuery(String query) {
    _searchDebounce?.cancel();
    state = state.copyWith(searchQuery: query);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      // La búsqueda se filtra reactivamente en la UI desde inventoryProvider
      // — no requiere llamada adicional al servidor.
    });
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    state = state.copyWith(searchQuery: '');
  }

  // ── Carrito — operaciones ─────────────────────────────────────────────────

  /// Añade un producto del inventario al carrito.
  /// Si ya existe, incrementa la cantidad.
  void addProduct(Product product, {int qty = 1}) {
    final existing =
        state.items.where((i) => i.productId == product.id).firstOrNull;

    if (existing != null) {
      _updateItem(existing.id, existing.quantity + qty);
    } else {
      final newItem = CartItem(
        id: _generateId(),
        productId: product.id,
        name: product.name,
        unitPriceMxn: product.priceMxn,
        quantity: qty,
        imageUrl: product.imageUrl,
      );
      state = state.copyWith(items: [...state.items, newItem]);
    }
  }

  /// Añade un producto al vuelo (sin ID de inventario).
  void addOnTheFly({
    required String name,
    required double priceMxn,
    int qty = 1,
  }) {
    final newItem = CartItem(
      id: _generateId(),
      productId: null,
      name: name,
      unitPriceMxn: priceMxn,
      quantity: qty,
      isOnTheFly: true,
    );
    state = state.copyWith(items: [...state.items, newItem]);
  }

  /// Actualiza la cantidad de un ítem. Si qty <= 0, lo elimina.
  void updateQty(String itemId, int qty) {
    if (qty <= 0) {
      removeItem(itemId);
      return;
    }
    _updateItem(itemId, qty);
  }

  /// Incrementa en 1 la cantidad de un ítem.
  void increment(String itemId) {
    final item = state.items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) return;
    _updateItem(itemId, item.quantity + 1);
  }

  /// Decrementa en 1 la cantidad. Mínimo 1 — usar removeItem para eliminar.
  void decrement(String itemId) {
    final item = state.items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) return;
    if (item.quantity > 1) {
      _updateItem(itemId, item.quantity - 1);
    }
    // qty == 1: no hace nada — el usuario debe usar el botón papelera explícitamente
  }

  /// Elimina un ítem del carrito por su ID.
  void removeItem(String itemId) {
    state = state.copyWith(
      items: state.items.where((i) => i.id != itemId).toList(),
    );
  }

  /// Vacía el carrito completo y limpia cualquier error.
  void clear() {
    state = const CartState();
  }

  // ── Checkout ─────────────────────────────────────────────────────────────

  /// Procesa el cobro vía POST /sales/checkout con uno o más métodos de
  /// pago (Tarea 7.2 — pagos mixtos).
  /// Lanza excepción si el API devuelve error (capturada por la pantalla).
  Future<CheckoutResult> checkout({
    required List<PaymentEntry> payments,
  }) async {
    if (state.isEmpty) throw Exception('El carrito está vacío.');

    state = state.copyWith(isProcessing: true, error: null);

    try {
      final cashierName = ref.read(currentUserNameProvider) ?? 'Cajero';
      final result = await _repo.checkout(
        items: state.items,
        payments: payments,
        cashierName: cashierName,
      );

      // Checkout exitoso: guarda el resultado y vacía el carrito
      state = CartState(lastCheckoutResult: result);
      return result;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  // ── Helpers privados ─────────────────────────────────────────────────────

  static int _idCounter = 0;

  void _updateItem(String itemId, int qty) {
    state = state.copyWith(
      items: state.items
          .map((i) => i.id == itemId ? i.copyWith(quantity: qty) : i)
          .toList(),
    );
  }

  String _generateId() => 'cart-${++_idCounter}';

  void cancelDebounce() => _searchDebounce?.cancel();
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final cartProvider = NotifierProvider<CartNotifier, CartState>(
  CartNotifier.new,
);

/// Provider derivado: filtra productos del inventario según la searchQuery.
/// Usado por product_search_results para el panel desplegable.
///
/// Importa el inventoryProvider para evitar una llamada extra al backend —
/// los productos ya están en memoria desde InventoryScreen.
