import 'package:equatable/equatable.dart';

/// Estado de una orden de compra — `PurchaseOrderStatus` en
/// `docs/api/components.yaml`.
///
/// La API solo define estos 5 valores (no existe `CONFIRMED`, pese a que la
/// descripción narrativa de `docs/api/purchases.yaml#POST /purchase-orders`
/// la menciona como paso intermedio — se sigue el schema, no la prosa).
enum PurchaseOrderStatus {
  draft,
  sent,
  partialReceived,
  received,
  cancelled;

  /// Valor enviado/recibido en `docs/api/purchases.yaml`.
  String get apiValue => switch (this) {
        PurchaseOrderStatus.draft => 'DRAFT',
        PurchaseOrderStatus.sent => 'SENT',
        PurchaseOrderStatus.partialReceived => 'PARTIAL_RECEIVED',
        PurchaseOrderStatus.received => 'RECEIVED',
        PurchaseOrderStatus.cancelled => 'CANCELLED',
      };

  String get label => switch (this) {
        PurchaseOrderStatus.draft => 'Borrador',
        PurchaseOrderStatus.sent => 'Enviado',
        PurchaseOrderStatus.partialReceived => 'Parcial',
        PurchaseOrderStatus.received => 'Recibido',
        PurchaseOrderStatus.cancelled => 'Cancelado',
      };

  /// Agrupación usada por el chip "Pendientes" del hub de Compras — incluye
  /// todo lo que aún no está completamente recibido ni cancelado.
  bool get isPending =>
      this == PurchaseOrderStatus.sent || this == PurchaseOrderStatus.partialReceived;
}

/// Línea de producto dentro de una orden de compra — `PurchaseOrderItem` en
/// `docs/api/components.yaml`.
///
/// [productName] es una conveniencia de UI (el schema real solo trae
/// `product_id`); el mock la incluye para no depender de una consulta
/// adicional al catálogo mientras Alan no entregue la Tarea 11.1.
class PurchaseOrderItem extends Equatable {
  const PurchaseOrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCostMxn,
    this.quantityReceived = 0,
  });

  final String productId;
  final String productName;
  final int quantity;
  final double unitCostMxn;
  final int quantityReceived;

  double get subtotalMxn => quantity * unitCostMxn;

  bool get isFullyReceived => quantityReceived >= quantity;

  PurchaseOrderItem copyWith({
    String? productName,
    int? quantity,
    double? unitCostMxn,
    int? quantityReceived,
  }) =>
      PurchaseOrderItem(
        productId: productId,
        productName: productName ?? this.productName,
        quantity: quantity ?? this.quantity,
        unitCostMxn: unitCostMxn ?? this.unitCostMxn,
        quantityReceived: quantityReceived ?? this.quantityReceived,
      );

  @override
  List<Object?> get props =>
      [productId, productName, quantity, unitCostMxn, quantityReceived];
}

/// Orden de compra — modelada sobre `PurchaseOrder` de
/// `docs/api/components.yaml`.
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
    required this.isCredit,
    required this.createdAt,
    this.warehouseId,
    this.expectedDeliveryDate,
    this.notes,
    this.receivedAt,
  });

  final String id;
  final String folio;
  final String supplierId;
  final String supplierName;
  final String? warehouseId;
  final PurchaseOrderStatus status;
  final List<PurchaseOrderItem> items;
  final bool isCredit;
  final DateTime? expectedDeliveryDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime? receivedAt;

  double get totalMxn =>
      items.fold<double>(0, (sum, item) => sum + item.subtotalMxn);

  int get itemCount => items.length;

  PurchaseOrder copyWith({
    PurchaseOrderStatus? status,
    List<PurchaseOrderItem>? items,
    DateTime? receivedAt,
  }) {
    return PurchaseOrder(
      id: id,
      folio: folio,
      supplierId: supplierId,
      supplierName: supplierName,
      warehouseId: warehouseId,
      status: status ?? this.status,
      items: items ?? this.items,
      isCredit: isCredit,
      expectedDeliveryDate: expectedDeliveryDate,
      notes: notes,
      createdAt: createdAt,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        folio,
        supplierId,
        supplierName,
        warehouseId,
        status,
        items,
        isCredit,
        expectedDeliveryDate,
        notes,
        createdAt,
        receivedAt,
      ];
}
