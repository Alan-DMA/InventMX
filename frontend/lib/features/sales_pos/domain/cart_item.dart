import 'package:equatable/equatable.dart';

/// Ítem dentro del carrito del POS.
///
/// Puede representar un producto del inventario (productId != null)
/// o un producto creado al vuelo / Lazy Loading (productId == null).
///
/// Trazabilidad: Constitución Art. VII (7.3 Lazy Loading Just-in-Time)
///              Doc. Maestro RF-09 · HU-11 / CU-12
class CartItem extends Equatable {
  const CartItem({
    required this.id,
    required this.name,
    required this.unitPriceMxn,
    required this.quantity,
    this.productId,
    this.imageUrl,
    this.isOnTheFly = false,
  });

  /// ID único del ítem en el carrito (UUID local, no el del producto).
  final String id;

  /// ID del producto en el inventario. Null si es al vuelo.
  final String? productId;

  /// Nombre del producto.
  final String name;

  /// Precio unitario en MXN al momento de agregar al carrito.
  final double unitPriceMxn;

  /// Cantidad de unidades en el carrito.
  final int quantity;

  /// URL de la imagen del producto (opcional).
  final String? imageUrl;

  /// true si el producto fue creado al vuelo (sin registro previo).
  final bool isOnTheFly;

  // ── Cálculos derivados ───────────────────────────────────────────────────

  /// Subtotal del ítem: quantity × unitPriceMxn.
  double get subtotalMxn => quantity * unitPriceMxn;

  // ── copyWith ─────────────────────────────────────────────────────────────

  CartItem copyWith({
    String? id,
    String? productId,
    String? name,
    double? unitPriceMxn,
    int? quantity,
    String? imageUrl,
    bool? isOnTheFly,
  }) {
    return CartItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      unitPriceMxn: unitPriceMxn ?? this.unitPriceMxn,
      quantity: quantity ?? this.quantity,
      imageUrl: imageUrl ?? this.imageUrl,
      isOnTheFly: isOnTheFly ?? this.isOnTheFly,
    );
  }

  @override
  List<Object?> get props => [id, productId, name, unitPriceMxn, quantity, isOnTheFly];
}
