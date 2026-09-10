import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Enum de tipo de movimiento
// Anclado al enum InventoryMovementType de docs/api/components.yaml
// ---------------------------------------------------------------------------

enum MovementType {
  purchaseIn,
  saleOut,
  manualAdjustmentIn,
  manualAdjustmentOut,
  transferIn,
  transferOut,
  waste,
  customerReturn,
  initialStock,
}

extension MovementTypeX on MovementType {
  /// Convierte desde el string del API (snake_case)
  static MovementType fromApi(String value) => switch (value) {
        'PURCHASE_IN'            => MovementType.purchaseIn,
        'SALE_OUT'               => MovementType.saleOut,
        'MANUAL_ADJUSTMENT_IN'   => MovementType.manualAdjustmentIn,
        'MANUAL_ADJUSTMENT_OUT'  => MovementType.manualAdjustmentOut,
        'TRANSFER_IN'            => MovementType.transferIn,
        'TRANSFER_OUT'           => MovementType.transferOut,
        'WASTE'                  => MovementType.waste,
        'CUSTOMER_RETURN'        => MovementType.customerReturn,
        'INITIAL_STOCK'          => MovementType.initialStock,
        _                        => MovementType.manualAdjustmentIn,
      };

  String get apiCode => switch (this) {
        MovementType.purchaseIn           => 'PURCHASE_IN',
        MovementType.saleOut              => 'SALE_OUT',
        MovementType.manualAdjustmentIn   => 'MANUAL_ADJUSTMENT_IN',
        MovementType.manualAdjustmentOut  => 'MANUAL_ADJUSTMENT_OUT',
        MovementType.transferIn           => 'TRANSFER_IN',
        MovementType.transferOut          => 'TRANSFER_OUT',
        MovementType.waste                => 'WASTE',
        MovementType.customerReturn       => 'CUSTOMER_RETURN',
        MovementType.initialStock         => 'INITIAL_STOCK',
      };

  String get label => switch (this) {
        MovementType.purchaseIn           => 'Compra recibida',
        MovementType.saleOut              => 'Venta',
        MovementType.manualAdjustmentIn   => 'Ajuste entrada',
        MovementType.manualAdjustmentOut  => 'Ajuste salida',
        MovementType.transferIn           => 'Traslado recibido',
        MovementType.transferOut          => 'Traslado enviado',
        MovementType.waste                => 'Merma',
        MovementType.customerReturn       => 'Devolución',
        MovementType.initialStock         => 'Stock inicial',
      };

  IconData get icon => switch (this) {
        MovementType.purchaseIn           => Icons.shopping_bag_rounded,
        MovementType.saleOut              => Icons.point_of_sale_rounded,
        MovementType.manualAdjustmentIn   => Icons.add_circle_outline_rounded,
        MovementType.manualAdjustmentOut  => Icons.remove_circle_outline_rounded,
        MovementType.transferIn           => Icons.arrow_downward_rounded,
        MovementType.transferOut          => Icons.arrow_upward_rounded,
        MovementType.waste                => Icons.warning_amber_rounded,
        MovementType.customerReturn       => Icons.assignment_return_rounded,
        MovementType.initialStock         => Icons.inventory_2_rounded,
      };

  Color get color => switch (this) {
        MovementType.purchaseIn           => AppColors.emerald,
        MovementType.saleOut              => AppColors.skyBlue,
        MovementType.manualAdjustmentIn   => AppColors.emerald,
        MovementType.manualAdjustmentOut  => AppColors.error,
        MovementType.transferIn           => AppColors.emerald,
        MovementType.transferOut          => AppColors.warning,
        MovementType.waste                => AppColors.warning,
        MovementType.customerReturn       => AppColors.skyBlue,
        MovementType.initialStock         => AppColors.onSurfaceMuted,
      };

  /// true si el movimiento incrementa el stock
  bool get isIncoming => switch (this) {
        MovementType.purchaseIn          => true,
        MovementType.manualAdjustmentIn  => true,
        MovementType.transferIn          => true,
        MovementType.customerReturn      => true,
        MovementType.initialStock        => true,
        _                                => false,
      };
}

// ---------------------------------------------------------------------------
// Modelo de dominio — InventoryMovement
// Anclado al schema InventoryMovement de docs/api/components.yaml
// ---------------------------------------------------------------------------

class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.productId,
    required this.warehouseId,
    required this.movementType,
    required this.quantity,
    required this.stockBefore,
    required this.stockAfter,
    required this.unitCostMxn,
    required this.createdAt,
    this.referenceId,
    this.referenceType,
    this.notes,
    this.userId,
  });

  final String id;
  final String productId;
  final String warehouseId;
  final MovementType movementType;

  /// Positivo para entradas, negativo para salidas (según schema del API).
  final int quantity;
  final int stockBefore;
  final int stockAfter;
  final double unitCostMxn;
  final DateTime createdAt;

  // Opcionales
  final String? referenceId;
  final String? referenceType; // SALE | PURCHASE | MANUAL | TRANSFER
  final String? notes;
  final String? userId;

  factory InventoryMovement.fromJson(Map<String, dynamic> json) {
    return InventoryMovement(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      warehouseId: json['warehouse_id'] as String,
      movementType: MovementTypeX.fromApi(json['movement_type'] as String),
      quantity: json['quantity'] as int,
      stockBefore: json['stock_before'] as int,
      stockAfter: json['stock_after'] as int,
      unitCostMxn: (json['unit_cost_mxn'] as num? ?? 0).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      referenceId: json['reference_id'] as String?,
      referenceType: json['reference_type'] as String?,
      notes: json['notes'] as String?,
      userId: json['user_id'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is InventoryMovement && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
