import '../domain/receipt_scan.dart';

/// Parser heurístico de las filas de texto que devuelve el OCR on-device.
///
/// **Sustituto temporal del backend.** La Tarea 12.1 de Alan
/// (`POST /purchases/parse-receipt`) está `⏳ Pendiente`; mientras tanto el
/// mismo trabajo se hace en el cliente con las reglas de abajo, calibradas
/// contra el formato de remisión de los repartidores mexicanos:
///
/// ```
/// 6   COCA COLA 600ML       18.50    111.00
/// 2 PZ PAN BIMBO GDE       $52.00   $104.00
/// CLORALEX 950ML       3    34.00    102.00
/// ```
///
/// Se trabaja por **posición de token**, no con un barrido global de dígitos:
/// los nombres de producto traen cifras dentro ("600ML", "45G", "1L") y un
/// `replaceAll` de números los destruiría.
class ReceiptLineParser {
  const ReceiptLineParser();

  /// Cifra con o sin separador de miles, con o sin `$`.
  static final RegExp _money =
      RegExp(r'^\$?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?$');

  /// Entero corto sin decimales — candidato a cantidad.
  static final RegExp _shortInt = RegExp(r'^\d{1,3}$');

  static final RegExp _hasLetters = RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]');

  /// Unidades que acompañan a la cantidad y no forman parte del nombre.
  static const _unitWords = {
    'PZ',
    'PZA',
    'PZAS',
    'PZS',
    'PIEZA',
    'PIEZAS',
    'CJ',
    'CAJA',
    'CAJAS',
    'KG',
    'KGS',
    'LT',
    'LTS',
    'PAQ',
    'PQT',
  };

  /// Palabras de encabezado o pie que nunca son un producto.
  static const _noiseWords = {
    'CANTIDAD',
    'CANT',
    'DESCRIPCION',
    'DESCRIPCIÓN',
    'CONCEPTO',
    'UNIDAD',
    'PRECIO',
    'IMPORTE',
    'SUBTOTAL',
    'IVA',
    'RFC',
    'FOLIO',
    'FACTURA',
    'REMISION',
    'REMISIÓN',
    'FECHA',
    'CLIENTE',
    'PROVEEDOR',
    'FIRMA',
    'GRACIAS',
    'SUCURSAL',
    'VENDEDOR',
    'RUTA',
  };

  ReceiptParseResult parseRows(List<String> rows) {
    final cleaned =
        rows.map((r) => r.trim()).where((r) => r.length > 2).toList();
    if (cleaned.isEmpty) return const ReceiptParseResult.empty();

    final items = <DetectedReceiptItem>[];
    double? total;

    for (final row in cleaned) {
      final upper = row.toUpperCase();

      if (_looksLikeTotal(upper)) {
        total ??= _lastAmountIn(row);
        continue;
      }
      if (_isNoise(upper)) continue;

      final item = _parseItemRow(row);
      if (item != null) items.add(item);
    }

    return ReceiptParseResult(
      items: items,
      detectedSupplier: _detectSupplier(cleaned),
      detectedTotalMxn: total,
      rowsRead: cleaned.length,
    );
  }

  // ── Clasificación de filas ────────────────────────────────────────────────

  bool _looksLikeTotal(String upper) =>
      upper.contains('TOTAL') && !upper.contains('SUBTOTAL');

  bool _isNoise(String upper) {
    final tokens = upper.split(RegExp(r'[\s:.]+'));
    final noiseHits = tokens.where(_noiseWords.contains).length;
    // Dos o más palabras de encabezado en la misma fila = cabecera de tabla.
    if (noiseHits >= 2) return true;
    // Una sola palabra de encabezado y ninguna otra palabra con letras.
    return noiseHits == 1 &&
        tokens.where((t) => t.isNotEmpty && _hasLetters.hasMatch(t)).length == 1;
  }

  String? _detectSupplier(List<String> rows) {
    for (final row in rows.take(4)) {
      final upper = row.toUpperCase();
      if (_isNoise(upper) || _looksLikeTotal(upper)) continue;
      final tokens = row.split(RegExp(r'\s+'));
      if (tokens.any(_money.hasMatch)) continue;
      if (_hasLetters.allMatches(row).length >= 4) return row;
    }
    return null;
  }

  // ── Parseo de una fila de producto ────────────────────────────────────────

  DetectedReceiptItem? _parseItemRow(String row) {
    final tokens =
        row.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.length < 2) return null;

    // Cola numérica: hasta 3 tokens finales que son cifras.
    final tail = <String>[];
    var cut = tokens.length;
    while (cut > 0 && tail.length < 3 && _money.hasMatch(tokens[cut - 1])) {
      tail.insert(0, tokens[cut - 1]);
      cut--;
    }
    if (tail.isEmpty) return null;

    var head = tokens.sublist(0, cut);
    int? quantity;

    // Cantidad al inicio: "6 COCA COLA ..." o "2 PZ PAN BIMBO ...".
    if (head.isNotEmpty && _shortInt.hasMatch(head.first)) {
      quantity = int.tryParse(head.first);
      head = head.sublist(1);
      if (head.isNotEmpty && _unitWords.contains(head.first.toUpperCase())) {
        head = head.sublist(1);
      }
    }

    // Cantidad embebida en la cola: "CLORALEX 950ML  3  34.00  102.00".
    if (quantity == null && tail.length == 3 && _shortInt.hasMatch(tail.first)) {
      quantity = int.tryParse(tail.first);
      tail.removeAt(0);
    }

    final amounts = tail.map(_toAmount).whereType<double>().toList();
    if (amounts.isEmpty) return null;

    final double? unitPrice;
    final double? subtotal;
    if (amounts.length >= 2) {
      unitPrice = amounts[amounts.length - 2];
      subtotal = amounts.last;
    } else {
      unitPrice = amounts.single;
      subtotal = null;
    }

    final name = head
        .join(' ')
        .replaceAll(RegExp(r'^[^\wÁÉÍÓÚÑáéíóúñ]+'), '')
        .trim();
    if (name.isEmpty || !_hasLetters.hasMatch(name)) return null;

    return _reconcile(
      name: name,
      quantity: quantity,
      unitPrice: unitPrice,
      subtotal: subtotal,
    );
  }

  /// Cruza cantidad × precio contra el importe del renglón y completa lo que
  /// falte. Es lo que más sube la precisión: la factura siempre trae el
  /// importe, así que funciona como checksum de lo que leyó el OCR.
  DetectedReceiptItem _reconcile({
    required String name,
    required int? quantity,
    required double? unitPrice,
    required double? subtotal,
  }) {
    var confidence = 0.5;
    var qty = quantity;
    var price = unitPrice;
    var total = subtotal;

    if (qty != null && price != null && total != null) {
      if (_matches(qty * price, total)) {
        confidence = 0.95;
      } else if (_matches(qty * total, price)) {
        // El OCR leyó las columnas en orden inverso.
        final swapped = price;
        price = total;
        total = swapped;
        confidence = 0.8;
      } else {
        final derived = (total / price).round();
        if (derived > 0 && _matches(derived * price, total)) {
          qty = derived;
          confidence = 0.7;
        } else {
          confidence = 0.45;
        }
      }
    } else if (qty == null && price != null && total != null) {
      final derived = (total / price).round();
      if (derived > 0 && _matches(derived * price, total)) {
        qty = derived;
        confidence = 0.75;
      } else {
        confidence = 0.5;
      }
    } else if (qty != null && price != null && total == null) {
      total = qty * price;
      confidence = 0.7;
    } else {
      confidence = 0.4;
    }

    return DetectedReceiptItem(
      name: name,
      quantity: qty,
      unitPriceMxn: price,
      subtotalMxn: total,
      confidence: confidence,
    );
  }

  /// Tolerancia del 2% (mínimo 50 centavos) — el OCR confunde puntos y comas
  /// en impresiones de matriz de punto.
  bool _matches(double a, double b) {
    final tolerance = (b.abs() * 0.02).clamp(0.5, double.infinity);
    return (a - b).abs() <= tolerance;
  }

  double? _toAmount(String token) =>
      double.tryParse(token.replaceAll(RegExp(r'[\$,]'), ''));

  double? _lastAmountIn(String row) {
    for (final token in row.split(RegExp(r'\s+')).reversed) {
      if (_money.hasMatch(token)) return _toAmount(token);
    }
    return null;
  }
}
