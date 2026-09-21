import 'package:equatable/equatable.dart';

import 'public_catalog.dart';

/// Cómo recibe el cliente su pedido — `DeliveryMethod` del backend.
enum DeliveryMethod {
  pickup('PICKUP', 'Recoger en tienda'),
  delivery('DELIVERY', 'A domicilio');

  const DeliveryMethod(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// Cómo piensa pagar — `PaymentMethodPreview` del backend. Es una intención
/// que viaja en el mensaje; el cobro real pasa en la tienda.
enum PaymentMethodPreview {
  cash('CASH', 'Efectivo'),
  transfer('TRANSFER', 'Transferencia / SPEI'),
  cardOnDelivery('CARD_ON_DELIVERY', 'Tarjeta al recibir');

  const PaymentMethodPreview(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// Un producto en el carrito del cliente.
class CartLine extends Equatable {
  const CartLine({required this.product, required this.quantity, this.notes});

  final PublicCatalogProduct product;
  final int quantity;
  final String? notes;

  double get subtotalMxn => product.priceMxn * quantity;

  /// `notes` usa el patrón `Function()` para poder **borrar** la nota
  /// (`() => null`) y no solo cambiarla (U-09).
  CartLine copyWith({int? quantity, String? Function()? notes}) => CartLine(
        product: product,
        quantity: quantity ?? this.quantity,
        notes: notes == null ? this.notes : notes(),
      );

  @override
  List<Object?> get props => [product, quantity, notes];
}

/// Lo que el cliente llena antes de enviar — `WhatsAppOrderBuildRequest`.
class WhatsAppOrderDraft extends Equatable {
  const WhatsAppOrderDraft({
    required this.customerName,
    required this.lines,
    this.customerPhone,
    this.deliveryMethod = DeliveryMethod.pickup,
    this.deliveryAddress,
    this.paymentMethod = PaymentMethodPreview.cash,
    this.cashTenderedMxn,
    this.orderNotes,
  });

  final String customerName;
  final String? customerPhone;
  final DeliveryMethod deliveryMethod;
  final String? deliveryAddress;
  final PaymentMethodPreview paymentMethod;

  /// "¿Con cuánto pagas?" — solo aplica en efectivo; permite calcular el
  /// cambio en el mensaje para que el tendero lo lleve listo.
  final double? cashTenderedMxn;
  final String? orderNotes;
  final List<CartLine> lines;

  double get subtotalMxn =>
      lines.fold<double>(0, (sum, l) => sum + l.subtotalMxn);

  WhatsAppOrderDraft copyWith({
    String? customerName,
    String? deliveryAddress,
  }) =>
      WhatsAppOrderDraft(
        customerName: customerName ?? this.customerName,
        customerPhone: customerPhone,
        deliveryMethod: deliveryMethod,
        deliveryAddress: deliveryAddress ?? this.deliveryAddress,
        paymentMethod: paymentMethod,
        cashTenderedMxn: cashTenderedMxn,
        orderNotes: orderNotes,
        lines: lines,
      );

  @override
  List<Object?> get props => [
        customerName,
        customerPhone,
        deliveryMethod,
        deliveryAddress,
        paymentMethod,
        cashTenderedMxn,
        orderNotes,
        lines,
      ];
}

/// Lo que devuelve el backend (o el formateador local) — `WhatsAppOrderBuildResponse`.
class WhatsAppOrderBuild extends Equatable {
  const WhatsAppOrderBuild({
    required this.waLink,
    required this.formattedText,
    required this.subtotalMxn,
    required this.totalMxn,
    required this.itemCount,
    this.deliveryFeeMxn = 0,
    this.changeMxn,
  });

  final Uri waLink;
  final String formattedText;
  final double subtotalMxn;
  final double deliveryFeeMxn;
  final double totalMxn;
  final double? changeMxn;
  final int itemCount;

  @override
  List<Object?> get props => [
        waLink,
        formattedText,
        subtotalMxn,
        deliveryFeeMxn,
        totalMxn,
        changeMxn,
        itemCount,
      ];
}

/// El pedido no pasa las reglas de la tienda — mismos casos que devuelve el
/// backend como 422, con el texto listo para mostrar.
class OrderRejected implements Exception {
  const OrderRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Pedido registrado — lo que la tienda ve al abrir el enlace del ticket.
///
/// Iteración 3 de QA (Eduardo): el mensaje de WhatsApp lleva solo folio,
/// total y **enlace**; el pedido completo vive aquí, en el servidor. Editar
/// el texto del chat no cambia nada porque la tienda abre el ticket.
class SavedOrder extends Equatable {
  const SavedOrder({
    required this.folio,
    required this.slug,
    required this.issuedAt,
    required this.draft,
    required this.totals,
    this.status = OrderStatus.newOrder,
    this.statusChangedAt,
    this.cancelReason,
    this.storeEditedAt,
    this.updatedAt,
    this.accessKey,
  });

  final String folio;
  final String slug;
  final DateTime issuedAt;
  final WhatsAppOrderDraft draft;
  final WhatsAppOrderBuild totals;

  /// Clave del enlace del ticket (`…/pedido/{folio}?k=`). El folio solo es
  /// adivinable; sin la clave el ticket público no abre. La recibe quien
  /// registró el pedido y el tendero; el GET público no la devuelve.
  final String? accessKey;

  /// Estado del lado de la tienda — visible también en el ticket público
  /// ("Listo para recoger"), que es el único feedback que la app le da al
  /// cliente sin inventar un canal nuevo (su canal es el chat).
  final OrderStatus status;
  final DateTime? statusChangedAt;
  final CancelReason? cancelReason;

  /// Última edición hecha por la tienda tras cambios acordados por chat. El
  /// ticket público la anuncia para que el enlace nunca mienta.
  final DateTime? storeEditedAt;

  /// Versión para concurrencia optimista (`expected_updated_at`).
  final DateTime? updatedAt;

  int get itemCount => draft.lines.fold(0, (n, l) => n + l.quantity);

  SavedOrder copyWith({
    WhatsAppOrderDraft? draft,
    WhatsAppOrderBuild? totals,
    OrderStatus? status,
    DateTime? statusChangedAt,
    CancelReason? Function()? cancelReason,
    DateTime? storeEditedAt,
    DateTime? updatedAt,
    String? accessKey,
  }) =>
      SavedOrder(
        folio: folio,
        slug: slug,
        issuedAt: issuedAt,
        draft: draft ?? this.draft,
        totals: totals ?? this.totals,
        status: status ?? this.status,
        statusChangedAt: statusChangedAt ?? this.statusChangedAt,
        cancelReason:
            cancelReason == null ? this.cancelReason : cancelReason(),
        storeEditedAt: storeEditedAt ?? this.storeEditedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        accessKey: accessKey ?? this.accessKey,
      );

  @override
  List<Object?> get props => [
        folio,
        slug,
        issuedAt,
        draft,
        totals,
        status,
        statusChangedAt,
        cancelReason,
        storeEditedAt,
        updatedAt,
        accessKey,
      ];
}

/// Estado del pedido web — `CatalogOrderStatus` del backend. El mínimo que
/// responde "¿qué me falta hacer con esto?" en una tiendita: "visto" es una
/// marca automática, no un estado, y "en preparación" se dejó fuera a
/// propósito (decisión de Eduardo, Sep 20 2026).
enum OrderStatus {
  newOrder('NEW', 'Nuevo'),
  ready('READY', 'Listo'),
  delivered('DELIVERED', 'Entregado'),
  cancelled('CANCELLED', 'Cancelado');

  const OrderStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  bool get isActive => this == newOrder || this == ready;
  bool get isClosed => !isActive;

  static OrderStatus fromApi(String? value) => values.firstWhere(
        (s) => s.apiValue == value,
        orElse: () => OrderStatus.newOrder,
      );
}

/// Motivo de cancelación — un toque en la app, alimenta reportes.
enum CancelReason {
  customerCancelled('CUSTOMER_CANCELLED', 'El cliente canceló'),
  outOfStock('OUT_OF_STOCK', 'Sin existencias'),
  neverConfirmed('NEVER_CONFIRMED', 'Nunca confirmó'),
  duplicate('DUPLICATE', 'Pedido repetido'),
  spam('SPAM', 'Broma o pedido falso'),
  other('OTHER', 'Otro motivo');

  const CancelReason(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static CancelReason? fromApi(String? value) {
    if (value == null) return null;
    for (final r in values) {
      if (r.apiValue == value) return r;
    }
    return CancelReason.other;
  }
}

/// El folio no corresponde a ningún pedido de esa tienda.
class OrderNotFound implements Exception {
  const OrderNotFound(this.folio);

  final String folio;
}
