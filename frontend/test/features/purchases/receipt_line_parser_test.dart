import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/purchases/data/receipt_line_parser.dart';

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
}
