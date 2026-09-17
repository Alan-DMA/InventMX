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
  /// Convierte desde el string del API (tolerante a backend enum, legacy snake_case y español)
  static MovementType fromApi(
    String value, {
    String? notes,
    String? reference,
  }) {
    final v = value.toUpperCase().trim();
    final n = (notes ?? '').toUpperCase();
    final r = (reference ?? '').toUpperCase();

    // 1. Carga inicial / Alta de producto (evaluación prioritaria para asientos de inventario inicial)
    if (v == 'INITIAL_STOCK' ||
        n.contains('INICIAL') ||
        n.contains('CARGA INICIAL') ||
        n.contains('ALTA DE PRODUCTO')) {
      return MovementType.initialStock;
    }

    // 2. Ventas (evaluar código oficial o palabra completa 'VENTA', NUNCA substring para evitar 'INVENTARIO')
    if (v == 'SALE_EXIT' ||
        v == 'SALE_OUT' ||
        v == 'VENTA' ||
        r.startsWith('NV-') ||
        RegExp(r'\bVENTA(S)?\b').hasMatch(n)) {
      return MovementType.saleOut;
    }

    // 3. Devolución / Cancelación de venta
    if (v == 'SALE_RETURN' ||
        v == 'CUSTOMER_RETURN' ||
        v == 'SALE_CANCEL' ||
        v == 'DEVOLUCION' ||
        RegExp(r'\bDEVOLUCI(O|Ó)N\b').hasMatch(n) ||
        n.contains('CANCELACION')) {
      return MovementType.customerReturn;
    }

    // 4. Mermas / Desperdicio
    if (v == 'WASTE_MERMA' ||
        v == 'WASTE' ||
        v == 'MERMA' ||
        RegExp(r'\bMERMA(S)?\b').hasMatch(n) ||
        RegExp(r'\bDESPERDICIO\b').hasMatch(n)) {
      return MovementType.waste;
    }

    // 5. Traslados
    if (v == 'TRANSFER_OUT' || (v == 'TRASLADO' && n.contains('HACIA'))) {
      return MovementType.transferOut;
    }
    if (v == 'TRANSFER_IN' || (v == 'TRASLADO' && n.contains('DESDE'))) {
      return MovementType.transferIn;
    }
    if (v == 'TRASLADO') {
      return MovementType.transferOut;
    }

    // 6. Compras / Recepción proveedor
    if (v == 'PURCHASE_ENTRY' ||
        v == 'PURCHASE_IN' ||
        v == 'COMPRA' ||
        r.startsWith('OC-') ||
        RegExp(r'\bCOMPRA(S)?\b').hasMatch(n) ||
        RegExp(r'\bPROVEEDOR\b').hasMatch(n) ||
        n.contains('NOTA_ENTREGA') ||
        n.contains('FACTURA')) {
      return MovementType.purchaseIn;
    }

    // 7. Ajustes / Entradas / Salidas genéricas
    if (v == 'ADJUSTMENT_IN' ||
        v == 'MANUAL_ADJUSTMENT_IN' ||
        v == 'ENTRADA' ||
        v == 'LIBERACION' ||
        v == 'RESERVATION_RELEASE') {
      return MovementType.manualAdjustmentIn;
    }

    if (v == 'ADJUSTMENT_OUT' ||
        v == 'MANUAL_ADJUSTMENT_OUT' ||
        v == 'SALIDA' ||
        v == 'RESERVA' ||
        v == 'RESERVATION_HOLD') {
      return MovementType.manualAdjustmentOut;
    }

    return MovementType.manualAdjustmentIn;
  }

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
        MovementType.initialStock         => AppColors.emerald,
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
    final num? parsedQty = rawQty is num
        ? rawQty
        : (num.tryParse(rawQty.toString()) ?? double.tryParse(rawQty.toString()));
    int qty = parsedQty?.round() ?? 0;

    final rawBefore = json['previous_stock'] ?? json['stock_before'] ?? 0;
    final num? parsedBefore = rawBefore is num
        ? rawBefore
        : (num.tryParse(rawBefore.toString()) ?? double.tryParse(rawBefore.toString()));
    final int before = parsedBefore?.round() ?? 0;

    final rawAfter = json['new_stock'] ?? json['stock_after'] ?? 0;
    final num? parsedAfter = rawAfter is num
        ? rawAfter
        : (num.tryParse(rawAfter.toString()) ?? double.tryParse(rawAfter.toString()));
    final int after = parsedAfter?.round() ?? 0;

    final rawCost = json['unit_cost_mxn'] ?? json['unit_cost_usd'] ?? 0;
    final double cost = rawCost is num
        ? rawCost.toDouble()
        : (double.tryParse(rawCost.toString()) ?? 0.0);

    DateTime parsedDate;
    if (json['created_at'] != null) {
      parsedDate = DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    final typeStr = (json['type'] ?? json['movement_type'] ?? '').toString();
    final refId = (json['reference_document'] ?? json['reference_id'])?.toString();
    final notes = json['notes']?.toString();

    final movementType = MovementTypeX.fromApi(typeStr, notes: notes, reference: refId);

    // Si es un egreso de inventario y la cantidad viene positiva en backend, normalizar con signo negativo
    if (!movementType.isIncoming && qty > 0) {
      qty = -qty;
    } else if (movementType.isIncoming && qty < 0) {
      qty = qty.abs();
    }

    return InventoryMovement(
      id: (json['id'] ?? '').toString(),
      productId: (json['product_id'] ?? '').toString(),
      productName: json['product_name']?.toString(),
      warehouseId: (json['warehouse_id'] ?? '').toString(),
      warehouseName: json['warehouse_name']?.toString(),
      movementType: movementType,
      quantity: qty,
      stockBefore: before,
      stockAfter: after,
      unitCostMxn: cost,
      createdAt: parsedDate,
      referenceId: refId,
      referenceType: json['reference_type']?.toString(),
      notes: notes,
      userId: json['user_id']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is InventoryMovement && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
