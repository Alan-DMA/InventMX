import 'cart_item.dart';
import 'payment_entry.dart';

/// Resultado de un checkout exitoso.
///
/// Incluye una copia (`items`, `payments`) del carrito al momento del cobro
/// para poder construir el ticket/comprobante — el carrito real se vacía
/// inmediatamente después del checkout (ver `CartNotifier.checkout`).
class CheckoutResult {
  const CheckoutResult({
    required this.saleId,
    required this.folio,
    required this.totalMxn,
    required this.totalPaidMxn,
    required this.changeGivenMxn,
    required this.items,
    required this.payments,
    required this.cashierName,
    required this.completedAt,
  });

  final String saleId;
  final String folio;
  final double totalMxn;
  final double totalPaidMxn;
  final double changeGivenMxn;
  final List<CartItem> items;
  final List<PaymentEntry> payments;
  final String cashierName;
  final DateTime completedAt;
}

/// Estado completo del carrito del POS.
class CartState {
  const CartState({
    this.items = const [],
    this.isProcessing = false,
    this.error,
    this.lastCheckoutResult,
    this.searchQuery = '',
  });

  final List<CartItem> items;
  final bool isProcessing;
  final String? error;
  final CheckoutResult? lastCheckoutResult;

  /// Texto de búsqueda activo en la barra superior.
  final String searchQuery;

  // ── Cálculos derivados ───────────────────────────────────────────────────

  /// Total de unidades en el carrito (suma de cantidades).
  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  /// Total en MXN del carrito.
  double get totalMxn => items.fold(0.0, (sum, i) => sum + i.subtotalMxn);

  /// Número de líneas distintas en el carrito.
  int get lineCount => items.length;

  bool get isEmpty => items.isEmpty;
  bool get hasError => error != null;

  CartState copyWith({
    List<CartItem>? items,
    bool? isProcessing,
    Object? error = _keep,
    Object? lastCheckoutResult = _keep,
    String? searchQuery,
  }) {
    return CartState(
      items: items ?? this.items,
      isProcessing: isProcessing ?? this.isProcessing,
      error: identical(error, _keep) ? this.error : error as String?,
      lastCheckoutResult: identical(lastCheckoutResult, _keep)
          ? this.lastCheckoutResult
          : lastCheckoutResult as CheckoutResult?,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

const Object _keep = Object();
