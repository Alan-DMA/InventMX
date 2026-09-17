import 'package:equatable/equatable.dart';

/// De qué trata el aviso. Cada tipo sabe a dónde lleva al tocarlo.
enum NotificationKind {
  /// "Se está agotando la Coca-Cola 600ml" → ficha del producto.
  lowStock,

  /// "Superaste tus ventas del año pasado" → Reportes.
  salesMilestone,

  /// Pedido de la vitrina sin atender → abre el chat de quien lo hizo.
  whatsappOrder,

  /// Cuenta por pagar que vence → Compras / CxP.
  payableDue,
}

/// Aviso personalizado del negocio.
///
/// Vive en su propio apartado (no encima de la operación) porque son cosas
/// que importan pero no urgen: si no se revisan, no pasa nada grave — de ahí
/// que el acceso lleve un contador en vez de interrumpir con un diálogo.
class StoreNotification extends Equatable {
  const StoreNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.productId,
    this.customerPhone,
    this.orderFolio,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  /// [NotificationKind.lowStock] — a qué producto se refiere.
  final String? productId;

  /// [NotificationKind.whatsappOrder] — teléfono del cliente, para abrir el
  /// chat que originó el pedido.
  final String? customerPhone;
  final String? orderFolio;

  StoreNotification copyWith({bool? isRead}) => StoreNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        productId: productId,
        customerPhone: customerPhone,
        orderFolio: orderFolio,
      );

  @override
  List<Object?> get props => [
        id,
        kind,
        title,
        body,
        createdAt,
        isRead,
        productId,
        customerPhone,
        orderFolio
      ];
}
