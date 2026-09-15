import '../../../core/utils/ocr_helper.dart';
import '../domain/receipt_scan.dart';
import 'receipt_row_classifier.dart';

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
  const ReceiptLineParser({this.classifier = const ReceiptRowClassifier()});

  /// Decide qué renglones no son producto (cabecera, total, fecha, teléfono,
  /// RFC…). Ver `ReceiptRowClassifier` — Tarea 12.2, QA de ruido.
  final ReceiptRowClassifier classifier;

  /// Cifra con o sin separador de miles, con o sin `$`. La coma seguida de
  /// exactamente 2 dígitos al final es decimal ("100,00" — formato de
  /// órdenes de compra genéricas); seguida de 3 es millar ("1,500").
  static final RegExp _money =
      RegExp(r'^\$?(?:\d{1,3}(?:,\d{3})+|\d+)(?:[.,]\d{1,2})?\$?$');

  static final RegExp _decimalComma = RegExp(r',(\d{1,2})$');

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

  ReceiptParseResult parseRows(List<String> rows) {
    final cleaned =
        rows.map((r) => r.trim()).where((r) => r.length > 2).toList();
    if (cleaned.isEmpty) return const ReceiptParseResult.empty();

    final items = <DetectedReceiptItem>[];
    double? total;

    for (final row in cleaned) {
      final kind = classifier.classify(row);
      if (kind == ReceiptRowKind.total) {
        total ??= _lastAmountIn(row);
        continue;
      }
      if (kind.isNeverProduct) continue;

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

  // ── Mapeo de columnas (tabla detectada por `detectTable`) ─────────────────
  //
  // El parser por renglones de arriba adivina; aquí solo PROPONE y el usuario
  // confirma o corrige en `OcrColumnMappingScreen`. La propuesta se apoya en
  // el único checksum honesto de una factura: en algún par de columnas
  // numéricas, cantidad × precio da la columna de importe.

  /// Propone qué columna es nombre, cantidad y precio. Puede venir
  /// incompleto (campos en `null`) — la pantalla de mapeo le pide al usuario
  /// lo que falte. `null` si la tabla no da ni para eso.
  ReceiptColumnMapping? suggestMapping(OcrTable table) {
    if (table.isEmpty) return null;

    // Solo las filas que pueden ser producto: la cabecera y el total
    // desvían el perfil de cada columna ("CANTIDAD" no es una cifra), y una
    // fila de una sola celda es el proveedor o un título, no un renglón de
    // la tabla.
    final rows = table.cells.where((row) {
      final filled = row.where((c) => c.isNotEmpty).toList();
      if (filled.length < 2) return false;
      return classifier.classify(filled.join(' ')) == ReceiptRowKind.content;
    }).toList();
    if (rows.isEmpty) return null;

    final columns = List.generate(
        table.columnCount,
        (c) => _ColumnProfile(
              index: c,
              cells: [for (final row in rows) row[c]],
              numbersIn: _numbersIn,
              hasLetters: _hasLetters,
            ));

    _ColumnProfile? nameCandidate;
    for (final col in columns) {
      if (col.letterCells == 0) continue;
      if (nameCandidate == null ||
          col.letterCells > nameCandidate.letterCells) {
        nameCandidate = col;
      }
    }
    if (nameCandidate == null) return null;
    final name = nameCandidate;

    final numeric = columns
        .where((c) => c.index != name.index && c.isMostlyNumeric)
        .toList();
    if (numeric.isEmpty) return ReceiptColumnMapping(nameCol: name.index);

    // Checksum: (q, p, t) con q antes de p y t a la derecha de ambos, donde
    // q × p ≈ t en la mayoría de las filas con las tres celdas.
    _ColumnProfile? bestQ, bestP, bestT;
    var bestHits = 0;
    for (final q in numeric) {
      for (final p in numeric) {
        if (p.index <= q.index) continue;
        for (final t in numeric) {
          if (t.index <= p.index) continue;
          var hits = 0;
          var candidates = 0;
          for (var r = 0; r < rows.length; r++) {
            final qv = q.amountAt(r);
            final pv = p.amountAt(r);
            final tv = t.amountAt(r);
            if (qv == null || pv == null || tv == null) continue;
            if (tv <= 0) continue;
            candidates++;
            if (_matches(qv * pv, tv)) hits++;
          }
          if (candidates > 0 && hits * 2 > candidates && hits > bestHits) {
            bestHits = hits;
            bestQ = q;
            bestP = p;
            bestT = t;
          }
        }
      }
    }
    if (bestQ != null) {
      return ReceiptColumnMapping(
        nameCol: name.index,
        quantityCol: bestQ.index,
        priceCol: bestP!.index,
        subtotalCol: bestT!.index,
      );
    }

    // Sin checksum posible: enteros = cantidad, decimales = precio; si no se
    // distinguen, el orden de la factura (cantidad antes que precio).
    if (numeric.length == 1) {
      return ReceiptColumnMapping(
          nameCol: name.index, priceCol: numeric.single.index);
    }
    final withDecimals = numeric.where((c) => c.decimalCells > 0).toList();
    final integers = numeric.where((c) => c.decimalCells == 0).toList();
    if (withDecimals.isNotEmpty && integers.isNotEmpty) {
      return ReceiptColumnMapping(
        nameCol: name.index,
        quantityCol: integers.first.index,
        priceCol: withDecimals.first.index,
      );
    }
    return ReceiptColumnMapping(
      nameCol: name.index,
      quantityCol: numeric[0].index,
      priceCol: numeric[1].index,
    );
  }

  /// Convierte cada fila de la tabla en un producto según [mapping]. Salta
  /// cabeceras, totales y filas sin nombre. Si cantidad y precio apuntan a la
  /// misma columna (el OCR pegó dos celdas), se toman el 1º y 2º número.
  List<DetectedReceiptItem> applyMapping(
    OcrTable table,
    ReceiptColumnMapping mapping,
  ) {
    if (!mapping.isComplete || !mapping.fitsColumnCount(table.columnCount)) {
      return const [];
    }
    final items = <DetectedReceiptItem>[];
    for (final row in table.cells) {
      final rowText = row.where((c) => c.isNotEmpty).join(' ');
      if (classifier.classify(rowText).isNeverProduct) continue;

      final name = row[mapping.nameCol!]
          .replaceAll(RegExp(r'^[^\wÁÉÍÓÚÑáéíóúñ]+'), '')
          .trim();
      if (name.isEmpty || !_hasLetters.hasMatch(name)) continue;

      final int? quantity;
      final double? price;
      if (mapping.quantityCol == mapping.priceCol) {
        final numbers = _numbersIn(row[mapping.quantityCol!]);
        quantity = numbers.isNotEmpty ? numbers[0].round() : null;
        price = numbers.length > 1 ? numbers[1] : null;
      } else {
        quantity = _numbersIn(row[mapping.quantityCol!]).firstOrNull?.round();
        price = _numbersIn(row[mapping.priceCol!]).firstOrNull;
      }
      final subtotal =
          mapping.subtotalCol == null || mapping.subtotalCol! >= row.length
              ? null
              : _numbersIn(row[mapping.subtotalCol!]).lastOrNull;
      if (quantity == null && price == null) continue;

      items.add(_reconcile(
        name: name,
        quantity: quantity,
        unitPrice: price,
        subtotal: subtotal,
      ));
    }
    return items;
  }

  List<double> _numbersIn(String cell) => cell
      .split(RegExp(r'\s+'))
      .where(_money.hasMatch)
      .map(_toAmount)
      .whereType<double>()
      .toList();

  // ── Proveedor ─────────────────────────────────────────────────────────────

  /// Primer renglón "de texto" de la cabecera: con letras, sin cifras y que
  /// el clasificador no reconozca como fecha, contacto, referencia ni
  /// cabecera de tabla — "RFC: XAXX010101000" ya no puede salir como
  /// proveedor.
  String? _detectSupplier(List<String> rows) {
    for (final row in rows.take(6)) {
      if (classifier.classify(row) != ReceiptRowKind.content) continue;
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
    if (quantity == null &&
        tail.length == 3 &&
        _shortInt.hasMatch(tail.first)) {
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

    final name =
        head.join(' ').replaceAll(RegExp(r'^[^\wÁÉÍÓÚÑáéíóúñ]+'), '').trim();
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

    // Un precio leído como 0 (columna de descuento, dígito perdido) no puede
    // dividir: `(total / 0).round()` lanza en Dart.
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
        final derived = price > 0 ? (total / price).round() : 0;
        if (derived > 0 && _matches(derived * price, total)) {
          qty = derived;
          confidence = 0.7;
        } else {
          confidence = 0.45;
        }
      }
    } else if (qty == null && price != null && total != null) {
      final derived = price > 0 ? (total / price).round() : 0;
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

  double? _toAmount(String token) {
    var t = token.replaceAll(r'$', '');
    t = t.replaceAllMapped(_decimalComma, (m) => '.${m.group(1)}');
    return double.tryParse(t.replaceAll(',', ''));
  }

  double? _lastAmountIn(String row) {
    for (final token in row.split(RegExp(r'\s+')).reversed) {
      if (_money.hasMatch(token)) return _toAmount(token);
    }
    return null;
  }
}

/// Perfil numérico/alfabético de una columna de `OcrTable`, para que
/// `suggestMapping` decida cuál es nombre y cuáles son cifras.
class _ColumnProfile {
  _ColumnProfile({
    required this.index,
    required List<String> cells,
    required List<double> Function(String) numbersIn,
    required RegExp hasLetters,
  }) : _amounts = [for (final cell in cells) numbersIn(cell)] {
    for (var r = 0; r < cells.length; r++) {
      final cell = cells[r];
      if (cell.isEmpty) continue;
      nonEmpty++;
      final tokens = cell.split(RegExp(r'\s+'));
      // "2 PZ" es una cantidad, no un nombre: la celda es numérica si su
      // primer token es cifra, y solo cuenta como texto si no lo es.
      final startsNumeric =
          _amounts[r].isNotEmpty && RegExp(r'^\$?\d').hasMatch(tokens.first);
      if (startsNumeric) {
        numericCells++;
        if (tokens.any((t) => t.contains(RegExp(r'[.,]\d{1,2}$')))) {
          decimalCells++;
        }
      } else if (hasLetters.hasMatch(cell)) {
        letterCells++;
      }
    }
  }

  final int index;
  final List<List<double>> _amounts;

  int nonEmpty = 0;
  int letterCells = 0;
  int numericCells = 0;
  int decimalCells = 0;

  bool get isMostlyNumeric => nonEmpty > 0 && numericCells * 2 >= nonEmpty;

  /// Primera cifra de la celda en la fila [r], o `null`.
  double? amountAt(int r) =>
      r < _amounts.length ? _amounts[r].firstOrNull : null;
}
