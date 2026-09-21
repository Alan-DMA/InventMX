import 'package:equatable/equatable.dart';

import 'whatsapp_order.dart';

/// Pedido web tal como lo ve el tendero — `StoreOrderResponse` del backend:
/// el ticket (`SavedOrder`) más quién lo vio, quién lo atiende, la venta que
/// lo cobró y el historial de ediciones.
class StoreOrder extends Equatable {
  const StoreOrder({
    required this.order,
    this.seenAt,
    this.seenByName,
    this.attendedByName,
    this.editedByName,
    this.saleId,
    this.revisions = const [],
    this.possibleDuplicateOf,
  });

  final SavedOrder order;

  /// Se marca sola al abrir el pedido en la app (sin toque extra).
  final DateTime? seenAt;
  final String? seenByName;
  final String? attendedByName;
  final String? editedByName;

  /// Venta del POS que cobró este pedido ("Cobrar en caja").
  final String? saleId;

  /// Versiones anteriores, la más reciente al final — para "yo pedí 3".
  final List<OrderRevision> revisions;

  /// Folio de un pedido igual del mismo cliente minutos antes: el cliente
  /// tocó "enviar" dos veces. Sólo se avisa; cancelar es decisión del tendero.
  final String? possibleDuplicateOf;

  String get folio => order.folio;
  OrderStatus get status => order.status;
  bool get isSeen => seenAt != null;
  bool get canEdit => status.isActive;
  bool get canCharge => status.isActive && saleId == null;

  /// Un pedido cobrado en caja no se reabre desde aquí (se devuelve desde la
  /// venta) — el backend lo rechaza, la UI no lo ofrece.
  bool get canReopen => status.isClosed && saleId == null;

  StoreOrder copyWith({
    SavedOrder? order,
    DateTime? seenAt,
    String? seenByName,
    String? attendedByName,
    String? editedByName,
    String? Function()? saleId,
    List<OrderRevision>? revisions,
    String? Function()? possibleDuplicateOf,
  }) =>
      StoreOrder(
        order: order ?? this.order,
        seenAt: seenAt ?? this.seenAt,
        seenByName: seenByName ?? this.seenByName,
        attendedByName: attendedByName ?? this.attendedByName,
        editedByName: editedByName ?? this.editedByName,
        saleId: saleId == null ? this.saleId : saleId(),
        revisions: revisions ?? this.revisions,
        possibleDuplicateOf: possibleDuplicateOf == null
            ? this.possibleDuplicateOf
            : possibleDuplicateOf(),
      );

  @override
  List<Object?> get props => [
        order,
        seenAt,
        seenByName,
        attendedByName,
        editedByName,
        saleId,
        revisions,
        possibleDuplicateOf,
      ];
}

/// Instantánea previa de un pedido editado por la tienda.
class OrderRevision extends Equatable {
  const OrderRevision({
    required this.at,
    required this.deliveryMethod,
    required this.lines,
    required this.subtotalMxn,
    required this.deliveryFeeMxn,
    required this.totalMxn,
    this.byName,
    this.deliveryAddress,
    this.orderNotes,
  });

  final DateTime at;
  final String? byName;
  final DeliveryMethod deliveryMethod;
  final String? deliveryAddress;
  final String? orderNotes;
  final List<CartLine> lines;
  final double subtotalMxn;
  final double deliveryFeeMxn;
  final double totalMxn;

  @override
  List<Object?> get props => [
        at,
        byName,
        deliveryMethod,
        deliveryAddress,
        orderNotes,
        lines,
        subtotalMxn,
        deliveryFeeMxn,
        totalMxn,
      ];
}

/// Página de pedidos del tendero — `StoreOrderListResponse`. El badge
/// (`newCount`) siempre viene del servidor: si el socket se cae, el tendero
/// pierde inmediatez, no pedidos.
class StoreOrderList extends Equatable {
  const StoreOrderList({
    this.items = const [],
    this.total = 0,
    this.newCount = 0,
    this.activeCount = 0,
  });

  final List<StoreOrder> items;
  final int total;

  /// Pedidos nuevos que nadie ha abierto.
  final int newCount;

  /// Nuevos + listos.
  final int activeCount;

  StoreOrderList copyWith({
    List<StoreOrder>? items,
    int? total,
    int? newCount,
    int? activeCount,
  }) =>
      StoreOrderList(
        items: items ?? this.items,
        total: total ?? this.total,
        newCount: newCount ?? this.newCount,
        activeCount: activeCount ?? this.activeCount,
      );

  @override
  List<Object?> get props => [items, total, newCount, activeCount];
}

/// Qué cambia la tienda al editar un pedido (`StoreOrderEditRequest`).
class StoreOrderEdit extends Equatable {
  const StoreOrderEdit({
    required this.lines,
    required this.deliveryMethod,
    this.deliveryAddress,
    this.orderNotes,
    this.customerName,
    this.customerPhone,
    this.expectedUpdatedAt,
  });

  final List<CartLine> lines;
  final DeliveryMethod deliveryMethod;
  final String? deliveryAddress;
  final String? orderNotes;
  final String? customerName;
  final String? customerPhone;
  final DateTime? expectedUpdatedAt;

  @override
  List<Object?> get props => [
        lines,
        deliveryMethod,
        deliveryAddress,
        orderNotes,
        customerName,
        customerPhone,
        expectedUpdatedAt,
      ];
}

/// Evento del canal en vivo (`WS /ws/orders`).
enum OrderEventType { hello, ping, newOrder, updated, reconnected }

class OrderEvent extends Equatable {
  const OrderEvent(this.type, {this.order});

  const OrderEvent.reconnected() : this(OrderEventType.reconnected);

  final OrderEventType type;
  final StoreOrder? order;

  @override
  List<Object?> get props => [type, order];
}

/// Alguien más cambió el pedido (409): la app recarga, nunca pisa en silencio.
class OrderConflict implements Exception {
  const OrderConflict(this.message);

  final String message;

  @override
  String toString() => message;
}

/// El backend rechazó la acción (transición inválida, motivo faltante, etc.).
class OrderActionRejected implements Exception {
  const OrderActionRejected(this.message);

  final String message;

  @override
  String toString() => message;
}
