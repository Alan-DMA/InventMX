import 'package:equatable/equatable.dart';

/// Estado de una orden de compra — `PurchaseOrderStatus` real del backend
/// (`backend/app/modules/purchasing_suppliers/domain/purchase_order.py`).
///
/// El backend crea toda orden nueva ya en `CONFIRMED` (no usa `DRAFT`/`SENT`
/// en el flujo actual, reservados para una futura confirmación explícita del
/// proveedor) — `isPending` lo refleja para que el chip "Pendientes" no
/// quede vacío con órdenes recién creadas.
enum PurchaseOrderStatus {
  draft,
  sent,
  confirmed,
  partiallyReceived,
  received,
  cancelled;

  String get apiValue => switch (this) {
        PurchaseOrderStatus.draft => 'DRAFT',
        PurchaseOrderStatus.sent => 'SENT',
        PurchaseOrderStatus.confirmed => 'CONFIRMED',
        PurchaseOrderStatus.partiallyReceived => 'PARTIALLY_RECEIVED',
        PurchaseOrderStatus.received => 'RECEIVED',
        PurchaseOrderStatus.cancelled => 'CANCELLED',
      };

  static PurchaseOrderStatus fromApi(String value) => switch (value) {
        'DRAFT' => PurchaseOrderStatus.draft,
        'SENT' => PurchaseOrderStatus.sent,
        'CONFIRMED' => PurchaseOrderStatus.confirmed,
        'PARTIALLY_RECEIVED' => PurchaseOrderStatus.partiallyReceived,
        'RECEIVED' => PurchaseOrderStatus.received,
        'CANCELLED' => PurchaseOrderStatus.cancelled,
        _ => PurchaseOrderStatus.confirmed,
      };

  String get label => switch (this) {
        PurchaseOrderStatus.draft => 'Borrador',
        PurchaseOrderStatus.sent => 'Enviado',
        PurchaseOrderStatus.confirmed => 'Confirmado',
        PurchaseOrderStatus.partiallyReceived => 'Parcial',
        PurchaseOrderStatus.received => 'Recibido',
        PurchaseOrderStatus.cancelled => 'Cancelado',
      };

  /// Agrupación usada por el chip "Pendientes" del hub de Compras — incluye
  /// todo lo que aún no está completamente recibido ni cancelado.
  bool get isPending =>
      this == PurchaseOrderStatus.sent ||
      this == PurchaseOrderStatus.confirmed ||
      this == PurchaseOrderStatus.partiallyReceived;
}

/// Línea de producto dentro de una orden de compra — `PurchaseOrderItem` del
/// backend real (`schemas/purchase_order.py`).
///
/// [id] es `null` mientras la línea es un borrador local (aún no se envió al
/// backend); lo asigna el servidor al crear la orden y es obligatorio para
/// referenciar la línea en `POST /purchase-orders/{id}/receive`.
///
/// [quantity]/[quantityReceived] se mantienen como enteros (el backend acepta
/// `Decimal`, pero el negocio objetivo del MVP compra por pieza, no a granel
/// fraccionario) — simplificación deliberada, no una limitación del backend.
class PurchaseOrderItem extends Equatable {
  const PurchaseOrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCostMxn,
    this.id,
    this.productSku,
    this.quantityReceived = 0,
    this.lotNumber,
    this.expiryDate,
  });

  final String? id;
  final String productId;
  final String productName;
  final String? productSku;
  final int quantity;
  final double unitCostMxn;
  final int quantityReceived;
  final String? lotNumber;
  final DateTime? expiryDate;

  double get subtotalMxn => quantity * unitCostMxn;

  bool get isFullyReceived => quantityReceived >= quantity;

  PurchaseOrderItem copyWith({
    String? id,
    String? productName,
    String? productSku,
    int? quantity,
    double? unitCostMxn,
    int? quantityReceived,
    String? lotNumber,
    DateTime? expiryDate,
  }) =>
      PurchaseOrderItem(
        id: id ?? this.id,
        productId: productId,
        productName: productName ?? this.productName,
        productSku: productSku ?? this.productSku,
        quantity: quantity ?? this.quantity,
        unitCostMxn: unitCostMxn ?? this.unitCostMxn,
        quantityReceived: quantityReceived ?? this.quantityReceived,
        lotNumber: lotNumber ?? this.lotNumber,
        expiryDate: expiryDate ?? this.expiryDate,
      );

  @override
  List<Object?> get props => [
        id,
        productId,
        productName,
        productSku,
        quantity,
        unitCostMxn,
        quantityReceived,
        lotNumber,
        expiryDate,
      ];
}

/// Orden de compra — modelada sobre `PurchaseOrderResponse` del backend real
/// (`schemas/purchase_order.py`), no sobre `docs/api/components.yaml`
/// (desactualizado).
///
/// Trazabilidad: Constitución Art. I (1.2.8) · Doc. Maestro Sección 5.3
///              (RF-15) · HU-17 / CU-22
class PurchaseOrder extends Equatable {
  const PurchaseOrder({
    required this.id,
    required this.folio,
    required this.supplierId,
    required this.supplierName,
    required this.status,
    required this.items,
    required this.subtotalMxn,
    required this.taxMxn,
    required this.totalMxn,
    required this.createdAt,
    this.warehouseId,
    this.warehouseName,
    this.supplierRfc,
    this.expectedDeliveryDate,
    this.receivedDate,
    this.invoiceReference,
    this.notes,
    this.createdByUserId,
  });

  final String id;
  final String folio;
  final String supplierId;
  final String supplierName;
  final String? supplierRfc;
  final String? warehouseId;
  final String? warehouseName;
  final PurchaseOrderStatus status;
  final List<PurchaseOrderItem> items;
  final double subtotalMxn;
  final double taxMxn;
  final double totalMxn;
  final DateTime? expectedDeliveryDate;
  final DateTime? receivedDate;
  final String? invoiceReference;
  final String? notes;
  final String? createdByUserId;
  final DateTime createdAt;

  int get itemCount => items.length;

  PurchaseOrder copyWith({
    PurchaseOrderStatus? status,
    List<PurchaseOrderItem>? items,
    double? subtotalMxn,
    double? taxMxn,
    double? totalMxn,
    DateTime? receivedDate,
    String? invoiceReference,
  }) {
    return PurchaseOrder(
      id: id,
      folio: folio,
      supplierId: supplierId,
      supplierName: supplierName,
      supplierRfc: supplierRfc,
      warehouseId: warehouseId,
      warehouseName: warehouseName,
      status: status ?? this.status,
      items: items ?? this.items,
      subtotalMxn: subtotalMxn ?? this.subtotalMxn,
      taxMxn: taxMxn ?? this.taxMxn,
      totalMxn: totalMxn ?? this.totalMxn,
      expectedDeliveryDate: expectedDeliveryDate,
      receivedDate: receivedDate ?? this.receivedDate,
      invoiceReference: invoiceReference ?? this.invoiceReference,
      notes: notes,
      createdByUserId: createdByUserId,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        folio,
        supplierId,
        supplierName,
        supplierRfc,
        warehouseId,
        warehouseName,
        status,
        items,
        subtotalMxn,
        taxMxn,
        totalMxn,
        expectedDeliveryDate,
        receivedDate,
        invoiceReference,
        notes,
        createdByUserId,
        createdAt,
      ];
}
