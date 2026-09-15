import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Enum de tipo de movimiento
// Anclado al enum MovementType del backend y docs/api/components.yaml
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
  /// Convierte desde el string del API (tolerante a backend enum y legacy snake_case)
  static MovementType fromApi(String value) => switch (value.toUpperCase()) {
        'PURCHASE_ENTRY' || 'PURCHASE_IN'            => MovementType.purchaseIn,
        'SALE_EXIT' || 'SALE_OUT'                    => MovementType.saleOut,
        'ADJUSTMENT_IN' || 'MANUAL_ADJUSTMENT_IN'    => MovementType.manualAdjustmentIn,
        'ADJUSTMENT_OUT' || 'MANUAL_ADJUSTMENT_OUT'  => MovementType.manualAdjustmentOut,
        'TRANSFER_IN'                                => MovementType.transferIn,
        'TRANSFER_OUT'                               => MovementType.transferOut,
        'WASTE_MERMA' || 'WASTE'                     => MovementType.waste,
        'SALE_RETURN' || 'CUSTOMER_RETURN'           => MovementType.customerReturn,
        'INITIAL_STOCK'                              => MovementType.initialStock,
        _                                            => MovementType.manualAdjustmentIn,
      };

  String get apiCode => switch (this) {
        MovementType.purchaseIn           => 'PURCHASE_ENTRY',
        MovementType.saleOut              => 'SALE_EXIT',
        MovementType.manualAdjustmentIn   => 'ADJUSTMENT_IN',
        MovementType.manualAdjustmentOut  => 'ADJUSTMENT_OUT',
        MovementType.transferIn           => 'TRANSFER_IN',
        MovementType.transferOut          => 'TRANSFER_OUT',
        MovementType.waste                => 'WASTE_MERMA',
        MovementType.customerReturn       => 'SALE_RETURN',
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
// Anclado al schema InventoryMovementResponse del backend
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
    this.productName,
    this.warehouseName,
    this.referenceId,
    this.referenceType,
    this.notes,
    this.userId,
  });

  final String id;
  final String productId;
  final String? productName;
  final String warehouseId;
  final String? warehouseName;
  final MovementType movementType;

  /// Positivo para entradas, negativo para salidas (según schema del API).
  final int quantity;
  final int stockBefore;
  final int stockAfter;
  final double unitCostMxn;
  final DateTime createdAt;

  // Opcionales
  final String? referenceId;
  final String? referenceType;
  final String? notes;
  final String? userId;

  factory InventoryMovement.fromJson(Map<dynamic, dynamic> json) {
    final rawQty = json['quantity'] ?? 0;
    final int qty = rawQty is num ? rawQty.toInt() : (int.tryParse(rawQty.toString()) ?? 0);

    final rawBefore = json['previous_stock'] ?? json['stock_before'] ?? 0;
    final int before = rawBefore is num ? rawBefore.toInt() : (int.tryParse(rawBefore.toString()) ?? 0);

    final rawAfter = json['new_stock'] ?? json['stock_after'] ?? 0;
    final int after = rawAfter is num ? rawAfter.toInt() : (int.tryParse(rawAfter.toString()) ?? 0);

    final rawCost = json['unit_cost_mxn'] ?? 0;
    final double cost = rawCost is num ? rawCost.toDouble() : (double.tryParse(rawCost.toString()) ?? 0.0);

    DateTime parsedDate;
    if (json['created_at'] != null) {
      parsedDate = DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return InventoryMovement(
      id: (json['id'] ?? '').toString(),
      productId: (json['product_id'] ?? '').toString(),
      productName: json['product_name']?.toString(),
      warehouseId: (json['warehouse_id'] ?? '').toString(),
      warehouseName: json['warehouse_name']?.toString(),
      movementType: MovementTypeX.fromApi(json['movement_type']?.toString() ?? ''),
      quantity: qty,
      stockBefore: before,
      stockAfter: after,
      unitCostMxn: cost,
      createdAt: parsedDate,
      referenceId: json['reference_id']?.toString(),
      referenceType: json['reference_type']?.toString(),
      notes: json['notes']?.toString(),
      userId: json['user_id']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is InventoryMovement && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
