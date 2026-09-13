import 'package:equatable/equatable.dart';

import 'purchase_order.dart';

/// Producto detectado en una factura escaneada.
///
/// Refleja `items_detected` de `docs/api/purchases.yaml#/purchases/parse-receipt`
/// para que, cuando Alan entregue la Tarea 12.1, el cambio del parser local por
/// la respuesta real del backend no toque la UI.
class DetectedReceiptItem extends Equatable {
  const DetectedReceiptItem({
    required this.name,
    required this.confidence,
    this.quantity,
    this.unitPriceMxn,
    this.subtotalMxn,
  });

  final String name;
  final int? quantity;
  final double? unitPriceMxn;
  final double? subtotalMxn;

  /// 0.0 – 1.0. Por debajo de [lowConfidenceThreshold] la fila se marca en la
  /// pantalla de revisión para que el usuario la verifique antes de aceptar.
  final double confidence;

  static const double lowConfidenceThreshold = 0.6;

  bool get isLowConfidence => confidence < lowConfidenceThreshold;

  /// La línea está lista para convertirse en `PurchaseOrderItem` sin que el
  /// usuario tenga que completar nada.
  bool get isComplete =>
      name.trim().isNotEmpty &&
      (quantity ?? 0) > 0 &&
      (unitPriceMxn ?? 0) > 0;

  PurchaseOrderItem toPurchaseOrderItem(String draftId) => PurchaseOrderItem(
        productId: draftId,
        productName: name.trim(),
        quantity: quantity ?? 1,
        unitCostMxn: unitPriceMxn ?? 0,
      );

  DetectedReceiptItem copyWith({
    String? name,
    int? quantity,
    double? unitPriceMxn,
    double? subtotalMxn,
    double? confidence,
  }) =>
      DetectedReceiptItem(
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unitPriceMxn: unitPriceMxn ?? this.unitPriceMxn,
        subtotalMxn: subtotalMxn ?? this.subtotalMxn,
        confidence: confidence ?? this.confidence,
      );

  @override
  List<Object?> get props =>
      [name, quantity, unitPriceMxn, subtotalMxn, confidence];
}

/// Resultado completo del escaneo de una factura.
class ReceiptParseResult extends Equatable {
  const ReceiptParseResult({
    required this.items,
    this.detectedSupplier,
    this.detectedTotalMxn,
    this.rowsRead = 0,
  });

  const ReceiptParseResult.empty()
      : items = const [],
        detectedSupplier = null,
        detectedTotalMxn = null,
        rowsRead = 0;

  final List<DetectedReceiptItem> items;
  final String? detectedSupplier;
  final double? detectedTotalMxn;

  /// Filas de texto que devolvió el OCR — sirve para distinguir "no se detectó
  /// texto" de "se leyó la factura pero ninguna fila parecía un producto".
  final int rowsRead;

  bool get isEmpty => items.isEmpty;

  /// Suma de los subtotales de las líneas detectadas.
  double get itemsTotalMxn => items.fold<double>(
        0,
        (sum, i) => sum + (i.subtotalMxn ?? 0),
      );

  @override
  List<Object?> get props =>
      [items, detectedSupplier, detectedTotalMxn, rowsRead];
}
