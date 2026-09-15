import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/utils/ocr_helper.dart';
import 'package:nexus_app/features/purchases/data/receipt_line_parser.dart';
import 'package:nexus_app/features/purchases/domain/receipt_scan.dart';

/// Calibración del parser heurístico contra los formatos de remisión que
/// realmente entregan los repartidores mexicanos — equivalente en el cliente
/// a la Subtarea 12.1.3 de Alan.
void main() {
  const parser = ReceiptLineParser();

  group('renglones de producto', () {
    test('cantidad al inicio, precio unitario e importe al final', () {
      final result = parser.parseRows(['6 COCA COLA 600ML 18.50 111.00']);

      expect(result.items, hasLength(1));
      final item = result.items.single;
      expect(item.name, 'COCA COLA 600ML');
      expect(item.quantity, 6);
      expect(item.unitPriceMxn, 18.50);
      expect(item.subtotalMxn, 111.00);
      expect(item.confidence, greaterThan(0.9));
    });

    test('no destruye las cifras que forman parte del nombre', () {
      final result = parser.parseRows(['3 SABRITAS 45G 17.00 51.00']);

      expect(result.items.single.name, 'SABRITAS 45G');
      expect(result.items.single.quantity, 3);
    });

    test('acepta unidad después de la cantidad y el símbolo de pesos', () {
      final result = parser.parseRows([r'2 PZ PAN BIMBO GDE $52.00 $104.00']);

      final item = result.items.single;
      expect(item.name, 'PAN BIMBO GDE');
      expect(item.quantity, 2);
      expect(item.unitPriceMxn, 52.00);
      expect(item.subtotalMxn, 104.00);
    });

    test('cantidad embebida entre la descripción y los importes', () {
      final result = parser.parseRows(['CLORALEX 950ML 3 34.00 102.00']);

      final item = result.items.single;
      expect(item.name, 'CLORALEX 950ML');
      expect(item.quantity, 3);
      expect(item.unitPriceMxn, 34.00);
    });

    test('deriva la cantidad cuando la factura no la trae legible', () {
      final result = parser.parseRows(['LECHE LALA 1L 28.90 115.60']);

      final item = result.items.single;
      expect(item.quantity, 4);
      expect(item.confidence, greaterThan(0.7));
    });

    test('marca baja confianza cuando cantidad × precio no cuadra', () {
      final result = parser.parseRows(['4 GALLETAS MARIAS 12.00 99.00']);

      expect(result.items.single.isLowConfidence, isTrue);
    });

    test('calcula el importe faltante a partir de cantidad y precio', () {
      final result = parser.parseRows(['5 JABON ZOTE 21.50']);

      final item = result.items.single;
      expect(item.quantity, 5);
      expect(item.unitPriceMxn, 21.50);
      expect(item.subtotalMxn, closeTo(107.50, 0.001));
    });

    test('deja la cantidad vacía en vez de inventarla', () {
      final result = parser.parseRows(['ACEITE 123 1L 45.00']);

      expect(result.items.single.quantity, isNull);
      expect(result.items.single.isComplete, isFalse);
    });
  });

  group('filas que no son producto', () {
    test('descarta el encabezado de la tabla', () {
      final result =
          parser.parseRows(['CANTIDAD DESCRIPCION PRECIO IMPORTE']);

      expect(result.items, isEmpty);
    });

    test('descarta renglones sin ninguna cifra', () {
      expect(parser.parseRows(['ENTREGA EN MOSTRADOR']).items, isEmpty);
    });

    test('descarta renglones sin texto con letras', () {
      expect(parser.parseRows(['123 456']).items, isEmpty);
    });
  });

  group('lectura de la factura completa', () {
    final rows = [
      'DISTRIBUIDORA BIMBO NORTE',
      'REMISION 4471',
      'CANTIDAD DESCRIPCION PRECIO IMPORTE',
      '6 COCA COLA 600ML 18.50 111.00',
      r'2 PZ PAN BIMBO GDE $52.00 $104.00',
      'CLORALEX 950ML 3 34.00 102.00',
      'TOTAL 317.00',
    ];

    test('extrae los 3 productos, el proveedor y el total impreso', () {
      final result = parser.parseRows(rows);

      expect(result.items, hasLength(3));
      expect(result.detectedSupplier, 'DISTRIBUIDORA BIMBO NORTE');
      expect(result.detectedTotalMxn, 317.00);
      expect(result.rowsRead, rows.length);
      expect(result.itemsTotalMxn, closeTo(317.00, 0.001));
    });

    test('sin filas devuelve un resultado vacío', () {
      final result = parser.parseRows([]);

      expect(result.isEmpty, isTrue);
      expect(result.rowsRead, 0);
    });
  });

  // ── Mapeo de columnas (QA OCR — orden de compra de Eduardo) ─────────────

  group('suggestMapping / applyMapping', () {
    /// La orden de compra impresa con la que Eduardo probó el OCR: índice
    /// de renglón, descripción, unidades, precio unitario, % dto, precio con
    /// dto y total — con decimales de coma en la primera fila.
    const purchaseOrder = OcrTable(cells: [
      ['Artículo', 'Descripción', 'Unidades', 'Precio unitario', '% Dto.', 'Precio Dto.', 'Total'],
      ['1', 'ARTICULO 1', '20', '5', '0', '0,00', '100,00'],
      ['2', 'ARTICULO 2', '15', '1', '0', '0', '15'],
      ['3', 'ARTICULO 3', '30', '5', '0', '0', '150'],
      ['4', 'ARTICULO 4', '20', '2', '0', '0', '40'],
      ['5', 'ARTICULO 5', '3', '10', '0', '0', '30'],
      ['6', 'ARTICULO 6', '10', '10', '0', '0', '100'],
      ['7', 'ARTICULO 7', '10', '5', '0', '0', '50'],
      ['', '', '', '', '', 'Suma Total', ''],
    ]);

    test('propone descripción / unidades / precio unitario por checksum', () {
      final mapping = parser.suggestMapping(purchaseOrder)!;

      expect(mapping.nameCol, 1);
      expect(mapping.quantityCol, 2);
      expect(mapping.priceCol, 3);
      expect(mapping.subtotalCol, 6);
      expect(mapping.isComplete, isTrue);
    });

    test('genera los 7 productos con cantidad y precio correctos', () {
      final mapping = parser.suggestMapping(purchaseOrder)!;
      final items = parser.applyMapping(purchaseOrder, mapping);

      expect(items, hasLength(7));
      expect(items[0].name, 'ARTICULO 1');
      expect(items[0].quantity, 20);
      expect(items[0].unitPriceMxn, 5);
      expect(items[0].subtotalMxn, 100); // "100,00" con coma decimal
      expect(items[0].confidence, greaterThan(0.9));
      expect(items[1].quantity, 15);
      expect(items[1].unitPriceMxn, 1);
      expect(items[4].quantity, 3);
      expect(items[4].unitPriceMxn, 10);
      expect(items[6].subtotalMxn, 50);
      expect(items.every((i) => i.confidence > 0.9), isTrue);
    });

    test('un precio leído como 0 no lanza al reconciliar', () {
      final mapping = parser.suggestMapping(purchaseOrder)!;
      final withZeroPrice = mapping.copyWith(priceCol: () => 5);

      expect(() => parser.applyMapping(purchaseOrder, withZeroPrice),
          returnsNormally);
    });

    test('la remisión mexicana también se propone por checksum', () {
      const remision = OcrTable(cells: [
        ['CANTIDAD', 'DESCRIPCION', 'PRECIO', 'IMPORTE'],
        ['6', 'COCA COLA 600ML', '18.50', '111.00'],
        ['2 PZ', 'PAN BIMBO GDE', r'$52.00', r'$104.00'],
        ['3', 'SABRITAS 45G', '17.00', '51.00'],
      ]);

      final mapping = parser.suggestMapping(remision)!;
      expect(mapping.nameCol, 1);
      expect(mapping.quantityCol, 0);
      expect(mapping.priceCol, 2);

      final items = parser.applyMapping(remision, mapping);
      expect(items.map((i) => i.name), ['COCA COLA 600ML', 'PAN BIMBO GDE', 'SABRITAS 45G']);
      expect(items[1].quantity, 2);
      expect(items[1].unitPriceMxn, 52);
    });

    test('sin columna de importe, enteros = cantidad y decimales = precio', () {
      const table = OcrTable(cells: [
        ['COCA COLA', '6', '18.50'],
        ['PAN BIMBO', '2', '52.00'],
      ]);

      final mapping = parser.suggestMapping(table)!;
      expect(mapping.quantityCol, 1);
      expect(mapping.priceCol, 2);
      expect(mapping.subtotalCol, isNull);
    });

    test('con una sola columna numérica propone solo el precio', () {
      const table = OcrTable(cells: [
        ['COCA COLA', '18.50'],
      ]);

      final mapping = parser.suggestMapping(table)!;
      expect(mapping.priceCol, 1);
      expect(mapping.quantityCol, isNull);
      expect(mapping.isComplete, isFalse);
    });

    test('cantidad y precio en la misma columna toma 1º y 2º número', () {
      const table = OcrTable(cells: [
        ['COCA COLA', '6 18.50'],
      ]);
      const mapping =
          ReceiptColumnMapping(nameCol: 0, quantityCol: 1, priceCol: 1);

      final items = parser.applyMapping(table, mapping);
      expect(items.single.quantity, 6);
      expect(items.single.unitPriceMxn, 18.5);
    });

    test('un mapeo que no cabe en la tabla no genera nada', () {
      const table = OcrTable(cells: [
        ['COCA COLA', '6'],
      ]);
      const mapping =
          ReceiptColumnMapping(nameCol: 0, quantityCol: 1, priceCol: 7);

      expect(parser.applyMapping(table, mapping), isEmpty);
    });

    test('una tabla sin letras no da sugerencia', () {
      const table = OcrTable(cells: [
        ['1', '2'],
      ]);
      expect(parser.suggestMapping(table), isNull);
    });
  });

  group('ruido del proveedor y del documento (QA de ruido, Tarea 12.2)', () {
    /// La hoja completa como la lee el OCR: cabecera con datos del
    /// proveedor, la tabla, y el pie. `detectTable` deja fuera del grid los
    /// renglones de ruido con el clasificador del parser.
    final lines = <OcrLine>[
      _cell('ABARROTES LOPEZ S.A. DE C.V.', row: 0, col: 0),
      _cell('RFC: ALO010101XY9', row: 1, col: 0),
      _cell('Av. Insurgentes Sur 1234, Col. Centro', row: 2, col: 0),
      _cell('Tel.', row: 3, col: 0),
      _cell('55 1234 5678', row: 3, col: 1),
      _cell('Fecha', row: 4, col: 0),
      _cell('12/09/2026', row: 4, col: 1),
      _cell('Folio', row: 5, col: 0),
      _cell('A-00123', row: 5, col: 1),
      _cell('CANT', row: 6, col: 0),
      _cell('DESCRIPCION', row: 6, col: 1),
      _cell('PRECIO', row: 6, col: 2),
      _cell('IMPORTE', row: 6, col: 3),
      _cell('6', row: 7, col: 0),
      _cell('COCA COLA 600ML', row: 7, col: 1),
      _cell('18.50', row: 7, col: 2),
      _cell('111.00', row: 7, col: 3),
      _cell('2', row: 8, col: 0),
      _cell('PAN BIMBO GDE', row: 8, col: 1),
      _cell('52.00', row: 8, col: 2),
      _cell('104.00', row: 8, col: 3),
      _cell('3', row: 9, col: 0),
      _cell('CLORALEX 950ML', row: 9, col: 1),
      _cell('34.00', row: 9, col: 2),
      _cell('102.00', row: 9, col: 3),
      _cell('TOTAL', row: 10, col: 2),
      _cell('317.00', row: 10, col: 3),
      _cell('GRACIAS POR SU COMPRA', row: 11, col: 0),
      _cell('ventas@abarroteslopez.com', row: 12, col: 0),
    ];

    test('el grid solo trae la tabla y los ignorados se anuncian', () {
      final table = detectTable(lines, ignoreRow: parser.classifier.isNoise);

      expect(table.ignoredRows, [
        'RFC: ALO010101XY9',
        'Av. Insurgentes Sur 1234, Col. Centro',
        'Tel. 55 1234 5678',
        'Fecha 12/09/2026',
        'Folio A-00123',
        'ventas@abarroteslopez.com',
      ]);
      expect(table.columnCount, 4);
      expect(table.rowCount, 7); // proveedor, cabecera, 3 productos, total, pie
    });

    test('el mapeo produce solo los 3 productos, sin teléfono ni fecha', () {
      final table = detectTable(lines, ignoreRow: parser.classifier.isNoise);
      final mapping = parser.suggestMapping(table)!;
      final items = parser.applyMapping(table, mapping);

      expect(items.map((i) => i.name),
          ['COCA COLA 600ML', 'PAN BIMBO GDE', 'CLORALEX 950ML']);
      expect(items.map((i) => i.quantity), [6, 2, 3]);
      expect(items.map((i) => i.unitPriceMxn), [18.50, 52.00, 34.00]);
    });

    test('proveedor y total se detectan aunque vivan en el ruido', () {
      final table = detectTable(lines, ignoreRow: parser.classifier.isNoise);
      final result = parser.parseRows(table.rowTexts);

      expect(result.detectedSupplier, 'ABARROTES LOPEZ S.A. DE C.V.');
      expect(result.detectedTotalMxn, 317.00);
    });

    test('el RFC nunca sale como proveedor', () {
      final result = parser.parseRows([
        'RFC: XAXX010101000',
        'Tel. 55 1234 5678',
        'COMERCIALIZADORA DEL VALLE',
        '6 COCA COLA 600ML 18.50 111.00',
      ]);

      expect(result.detectedSupplier, 'COMERCIALIZADORA DEL VALLE');
    });

    test('la sugerencia de columnas no se contamina con las cifras del ruido',
        () {
      // Sin el filtro, "55 1234 5678" y "12/09/2026" perfilan columnas
      // numéricas falsas. Con él, la propuesta es la de la tabla real.
      final table = detectTable(lines, ignoreRow: parser.classifier.isNoise);
      final mapping = parser.suggestMapping(table)!;

      expect(mapping.nameCol, 1);
      expect(mapping.quantityCol, 0);
      expect(mapping.priceCol, 2);
      expect(mapping.subtotalCol, 3);
    });
  });
}

/// Celda en una cuadrícula regular — cada fila a 40 px, cada columna a
/// 150 px, como ML Kit devuelve un bloque por celda.
OcrLine _cell(String text, {required int row, required int col}) => OcrLine(
      text: text,
      boundingBox: Rect.fromLTWH(
        20 + col * 150.0,
        40 + row * 40.0,
        text.length * 7.0,
        20,
      ),
    );
