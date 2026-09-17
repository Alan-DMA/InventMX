import 'cart_item.dart';
import 'payment_entry.dart';

/// Cuánto de un `CartItem` de la venta original se devolvió en un reembolso.
///
/// `cartItemId` referencia `CartItem.id` — es lo más cercano al
/// `sale_item_id` de `POST /sales/{id}/refund` (docs/api/sales.yaml) que el
/// mock puede ofrecer sin un id de servidor real.
class RefundedLine {
  const RefundedLine({required this.cartItemId, required this.quantity});

  final String cartItemId;
  final int quantity;
}

/// Reembolso aplicado a una venta — total o parcial (Fase 2, acciones sobre
/// la venta). Una venta admite **un solo** evento de reembolso: no hay
/// reembolsos sucesivos sobre la misma venta en esta primera pasada.
///
/// Trazabilidad: docs/api/sales.yaml `POST /sales/{id}/refund`.
class SaleRefund {
  const SaleRefund({
    required this.refundedAt,
    required this.reason,
    required this.refundAmountMxn,
    required this.refundToStock,
    required this.lines,
  });

  final DateTime refundedAt;
  final String reason;
  final double refundAmountMxn;

  /// Si el producto devuelto regresa al inventario vendible. `false` para
  /// defectuoso/caducado (es merma, no una devolución de arrepentimiento).
  final bool refundToStock;

  /// Qué se devolvió, ítem por ítem. Vacía sólo si, por alguna razón, no
  /// hubo líneas que reembolsar (no debería ocurrir en la práctica).
  final List<RefundedLine> lines;
}

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
    this.refund,
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

  /// `null` mientras la venta no se ha reembolsado.
  final SaleRefund? refund;

  bool get isRefunded => refund != null;

  /// `totalMxn` es el hecho histórico (no se toca); esto es lo que de
  /// verdad entró a la caja después de un reembolso. Alimenta los
  /// agregados netos del kardex, "Vendido hoy" y Reportes.
  double get netTotalMxn => totalMxn - (refund?.refundAmountMxn ?? 0);

  CheckoutResult copyWith({SaleRefund? refund}) {
    return CheckoutResult(
      saleId: saleId,
      folio: folio,
      totalMxn: totalMxn,
      totalPaidMxn: totalPaidMxn,
      changeGivenMxn: changeGivenMxn,
      items: items,
      payments: payments,
      cashierName: cashierName,
      completedAt: completedAt,
      refund: refund ?? this.refund,
    );
  }
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
