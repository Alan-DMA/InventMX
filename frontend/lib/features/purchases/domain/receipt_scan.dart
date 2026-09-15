import 'dart:ui' show Rect;

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
      name.trim().isNotEmpty && (quantity ?? 0) > 0 && (unitPriceMxn ?? 0) > 0;

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

/// Qué columna de la tabla leída por el OCR trae cada dato del producto.
///
/// Índices de columna de `OcrTable`. Los tres campos que el usuario mapea son
/// obligatorios para generar productos; [subtotalCol] lo propone la
/// heurística cuando encuentra la columna de importe y solo sirve para el
/// checksum cantidad × precio — el usuario no lo elige.
class ReceiptColumnMapping extends Equatable {
  const ReceiptColumnMapping({
    this.nameCol,
    this.quantityCol,
    this.priceCol,
    this.subtotalCol,
  });

  final int? nameCol;
  final int? quantityCol;
  final int? priceCol;
  final int? subtotalCol;

  bool get isComplete =>
      nameCol != null && quantityCol != null && priceCol != null;

  /// Válido contra una tabla concreta — un mapeo recordado de otra factura
  /// puede apuntar a columnas que esta no tiene.
  bool fitsColumnCount(int columnCount) => [nameCol, quantityCol, priceCol]
      .every((c) => c == null || c < columnCount);

  ReceiptColumnMapping copyWith({
    int? Function()? nameCol,
    int? Function()? quantityCol,
    int? Function()? priceCol,
    int? Function()? subtotalCol,
  }) =>
      ReceiptColumnMapping(
        nameCol: nameCol == null ? this.nameCol : nameCol(),
        quantityCol: quantityCol == null ? this.quantityCol : quantityCol(),
        priceCol: priceCol == null ? this.priceCol : priceCol(),
        subtotalCol: subtotalCol == null ? this.subtotalCol : subtotalCol(),
      );

  Map<String, int?> toMap() => {
        'name': nameCol,
        'quantity': quantityCol,
        'price': priceCol,
        'subtotal': subtotalCol,
      };

  static ReceiptColumnMapping fromMap(Map raw) => ReceiptColumnMapping(
        nameCol: raw['name'] as int?,
        quantityCol: raw['quantity'] as int?,
        priceCol: raw['price'] as int?,
        subtotalCol: raw['subtotal'] as int?,
      );

  @override
  List<Object?> get props => [nameCol, quantityCol, priceCol, subtotalCol];
}

/// Resultado completo del escaneo de una factura.
class ReceiptParseResult extends Equatable {
  const ReceiptParseResult({
    required this.items,
    this.detectedSupplier,
    this.detectedTotalMxn,
    this.rowsRead = 0,
    this.ignoredRows = const [],
  });

  const ReceiptParseResult.empty()
      : items = const [],
        detectedSupplier = null,
        detectedTotalMxn = null,
        rowsRead = 0,
        ignoredRows = const [];

  final List<DetectedReceiptItem> items;
  final String? detectedSupplier;
  final double? detectedTotalMxn;

  /// Filas de texto que devolvió el OCR — sirve para distinguir "no se detectó
  /// texto" de "se leyó la factura pero ninguna fila parecía un producto".
  final int rowsRead;

  /// Renglones que el OCR leyó y se dejaron fuera por no ser producto
  /// (fecha, teléfono, RFC, dirección…) — Tarea 12.2, QA de ruido. La UI los
  /// muestra para que el descarte nunca sea silencioso.
  final List<String> ignoredRows;

  bool get isEmpty => items.isEmpty;

  /// Suma de los subtotales de las líneas detectadas.
  double get itemsTotalMxn => items.fold<double>(
        0,
        (sum, i) => sum + (i.subtotalMxn ?? 0),
      );

  ReceiptParseResult copyWith({
    List<DetectedReceiptItem>? items,
    String? detectedSupplier,
    double? detectedTotalMxn,
    int? rowsRead,
    List<String>? ignoredRows,
  }) =>
      ReceiptParseResult(
        items: items ?? this.items,
        detectedSupplier: detectedSupplier ?? this.detectedSupplier,
        detectedTotalMxn: detectedTotalMxn ?? this.detectedTotalMxn,
        rowsRead: rowsRead ?? this.rowsRead,
        ignoredRows: ignoredRows ?? this.ignoredRows,
      );

  @override
  List<Object?> get props =>
      [items, detectedSupplier, detectedTotalMxn, rowsRead, ignoredRows];
}

/// Lo que entra al OCR: una o varias imágenes (páginas) y, si vinieron de la
/// cámara, la región del marco guía a la que se limita la lectura.
///
/// Tarea 12.2 — Q-01 (región del visor) y Q-03 (PDF multipágina). Es el
/// contrato común de `ReceiptPhotoSource` (cámara) y `ReceiptFileSource`
/// (archivo), para que `PurchaseCreateScreen` procese ambos por el mismo
/// camino.
class ReceiptCapture extends Equatable {
  const ReceiptCapture({
    required this.imagePaths,
    this.region,
    this.portraitViewport = true,
  });

  ReceiptCapture.single(String path,
      {Rect? region, bool portraitViewport = true})
      : this(
          imagePaths: [path],
          region: region,
          portraitViewport: portraitViewport,
        );

  /// Rutas de las imágenes en orden de lectura: una foto, o una por página
  /// del PDF.
  final List<String> imagePaths;

  /// Región normalizada (0..1) del marco guía sobre la imagen derecha, o
  /// `null` para leer la imagen completa (archivos, o visor sin medir).
  final Rect? region;

  /// Orientación de la pantalla al disparar — necesaria para resolver la
  /// orientación de la foto (ver `resolveImageSpace`).
  final bool portraitViewport;

  @override
  List<Object?> get props => [imagePaths, region, portraitViewport];
}
