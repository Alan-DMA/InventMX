import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/utils/ocr_helper.dart';

OcrLine _line(String text, {required double top, required double left}) =>
    OcrLine(
      text: text,
      boundingBox: Rect.fromLTWH(left, top, 120, 20),
    );

void main() {
  group('groupLinesIntoRows', () {
    test('une en un renglón los bloques que comparten banda vertical', () {
      final rows = groupLinesIntoRows([
        _line('18.50', top: 100, left: 400),
        _line('COCA COLA 600ML', top: 102, left: 120),
        _line('6', top: 101, left: 20),
      ]);

      expect(rows, ['6 COCA COLA 600ML 18.50']);
    });

    test('ordena de izquierda a derecha dentro del renglón', () {
      final rows = groupLinesIntoRows([
        _line('IMPORTE', top: 50, left: 500),
        _line('CANTIDAD', top: 50, left: 10),
        _line('DESCRIPCION', top: 50, left: 100),
      ]);

      expect(rows.single, 'CANTIDAD DESCRIPCION IMPORTE');
    });

    test('separa renglones distintos y los devuelve de arriba hacia abajo', () {
      final rows = groupLinesIntoRows([
        _line('SEGUNDO', top: 200, left: 10),
        _line('PRIMERO', top: 100, left: 10),
      ]);

      expect(rows, ['PRIMERO', 'SEGUNDO']);
    });

    test('la tolerancia es relativa a la altura de la línea', () {
      // Bloques separados por 12 px con líneas de 20 px de alto: misma banda.
      final rows = groupLinesIntoRows([
        _line('A', top: 100, left: 10),
        _line('B', top: 112, left: 200),
      ]);

      expect(rows, hasLength(1));
    });

    test('descarta texto en blanco sin dejar renglones vacíos', () {
      final rows = groupLinesIntoRows([
        _line('   ', top: 100, left: 10),
        _line('', top: 300, left: 10),
      ]);

      expect(rows, isEmpty);
    });

    test('sin líneas devuelve una lista vacía', () {
      expect(groupLinesIntoRows([]), isEmpty);
    });
  });

  // ── Invariancia a rotación ───────────────────────────────────────────────
  //
  // Foto tomada con el teléfono en horizontal (bug real de Eduardo): la hoja
  // queda girada 90° dentro de la imagen y el texto se lee de arriba hacia
  // abajo (o de abajo hacia arriba, según el lado). Las mismas filas y el
  // mismo orden de lectura deben salir igual que con la hoja derecha.

  /// Tabla de 2 filas × 3 columnas en coordenadas "de hoja", luego girada a
  /// coordenadas de imagen. `rotate` mapea (x, y) de hoja → (x, y) de imagen
  /// y `direction` es el vector de lectura resultante.
  List<OcrLine> rotatedTable({
    required Offset Function(double x, double y) rotate,
    required Offset direction,
  }) {
    const cells = [
      // (texto, x de hoja, y de hoja, ancho)
      ('6', 20.0, 100.0, 20.0),
      ('COCA COLA', 120.0, 100.0, 150.0),
      ('18.50', 400.0, 100.0, 60.0),
      ('2', 20.0, 140.0, 20.0),
      ('PAN BIMBO', 120.0, 140.0, 150.0),
      ('52.00', 400.0, 140.0, 60.0),
    ];
    return [
      for (final (text, x, y, w) in cells)
        OcrLine(
          text: text,
          boundingBox: Rect.fromPoints(
            rotate(x, y),
            rotate(x + w, y + 20),
          ),
          direction: direction,
        ),
    ];
  }

  group('groupLinesIntoRows con la hoja girada', () {
    const expected = ['6 COCA COLA 18.50', '2 PAN BIMBO 52.00'];

    test('derecha (referencia)', () {
      final lines = rotatedTable(
        rotate: (x, y) => Offset(x, y),
        direction: const Offset(1, 0),
      );
      expect(groupLinesIntoRows(lines), expected);
    });

    test('girada 90° horario: el texto se lee de arriba hacia abajo', () {
      // Hoja (x, y) → imagen (W - y, x): el borde superior de la hoja queda
      // a la derecha de la imagen.
      final lines = rotatedTable(
        rotate: (x, y) => Offset(1000 - y, x),
        direction: const Offset(0, 1),
      );
      expect(groupLinesIntoRows(lines), expected);
    });

    test('girada 90° antihorario: el texto se lee de abajo hacia arriba', () {
      // Hoja (x, y) → imagen (y, H - x): el borde superior queda a la
      // izquierda.
      final lines = rotatedTable(
        rotate: (x, y) => Offset(y, 1000 - x),
        direction: const Offset(0, -1),
      );
      expect(groupLinesIntoRows(lines), expected);
    });

    test('de cabeza', () {
      final lines = rotatedTable(
        rotate: (x, y) => Offset(1000 - x, 1000 - y),
        direction: const Offset(-1, 0),
      );
      expect(groupLinesIntoRows(lines), expected);
    });
  });

  group('detectTable', () {
    test('separa columnas por solapamiento y deja vacío donde no hay celda',
        () {
      final table = detectTable([
        _line('CANTIDAD', top: 50, left: 10),
        _line('DESCRIPCION', top: 50, left: 150),
        _line('IMPORTE', top: 50, left: 400),
        _line('6', top: 100, left: 10),
        _line('COCA COLA 600ML', top: 100, left: 150),
        _line('111.00', top: 100, left: 400),
        _line('PAN BIMBO', top: 140, left: 150), // sin cantidad ni importe
      ]);

      expect(table.columnCount, 3);
      expect(table.cells, [
        ['CANTIDAD', 'DESCRIPCION', 'IMPORTE'],
        ['6', 'COCA COLA 600ML', '111.00'],
        ['', 'PAN BIMBO', ''],
      ]);
    });

    test('los números alineados a la derecha caen en la misma columna', () {
      // "5" es angosto y empieza más a la derecha que "150": mismo intervalo
      // de columna por solapamiento, no por inicio.
      final table = detectTable([
        const OcrLine(text: 'A', boundingBox: Rect.fromLTWH(10, 100, 40, 20)),
        const OcrLine(text: '150', boundingBox: Rect.fromLTWH(300, 100, 45, 20)),
        const OcrLine(text: 'B', boundingBox: Rect.fromLTWH(10, 140, 40, 20)),
        const OcrLine(text: '5', boundingBox: Rect.fromLTWH(330, 140, 15, 20)),
      ]);

      expect(table.columnCount, 2);
      expect(table.cells[0][1], '150');
      expect(table.cells[1][1], '5');
    });

    test('con la hoja girada devuelve la misma tabla', () {
      final lines = rotatedTable(
        rotate: (x, y) => Offset(1000 - y, x),
        direction: const Offset(0, 1),
      );
      final table = detectTable(lines);

      expect(table.cells, [
        ['6', 'COCA COLA', '18.50'],
        ['2', 'PAN BIMBO', '52.00'],
      ]);
    });

    test('sampleOf muestra las primeras celdas no vacías de la columna', () {
      const table = OcrTable(cells: [
        ['', 'A'],
        ['x', 'B'],
        ['', 'C'],
        ['', 'D'],
      ]);
      expect(table.sampleOf(1), 'A, B, C');
      expect(table.sampleOf(0), 'x');
    });

    test('sin líneas devuelve una tabla vacía', () {
      expect(detectTable([]).isEmpty, isTrue);
    });

    test('ignoreRow saca renglones del grid y los conserva en rowTexts', () {
      final table = detectTable(
        [
          _line('Tel. 55 1234 5678', top: 20, left: 10),
          _line('6', top: 100, left: 10),
          _line('COCA COLA', top: 100, left: 150),
          _line('18.50', top: 100, left: 400),
          _line('Fecha 12/09/2026', top: 180, left: 10),
        ],
        ignoreRow: (row) => row.contains('Tel.') || row.contains('Fecha'),
      );

      expect(table.cells, [
        ['6', 'COCA COLA', '18.50'],
      ]);
      expect(table.ignoredRows, ['Tel. 55 1234 5678', 'Fecha 12/09/2026']);
      // El parser por renglones sigue viendo la hoja completa, en orden.
      expect(table.rowTexts,
          ['Tel. 55 1234 5678', '6 COCA COLA 18.50', 'Fecha 12/09/2026']);
    });

    test('si se ignoran todos los renglones la tabla queda vacía pero anota',
        () {
      final table = detectTable(
        [_line('Fecha 12/09/2026', top: 20, left: 10)],
        ignoreRow: (_) => true,
      );

      expect(table.isEmpty, isTrue);
      expect(table.ignoredRows, ['Fecha 12/09/2026']);
      expect(table.rowTexts, ['Fecha 12/09/2026']);
    });

    test('una celda de ancho completo no ensancha las columnas', () {
      // Nombre del proveedor a lo ancho de la hoja arriba de la tabla. Antes
      // abría una columna gigante y las celdas siguientes caían todas ahí.
      final table = detectTable([
        const OcrLine(
          text: 'ABARROTES LOPEZ S.A. DE C.V.',
          boundingBox: Rect.fromLTWH(10, 20, 520, 20),
        ),
        _line('6', top: 100, left: 10),
        _line('COCA COLA', top: 100, left: 150),
        _line('18.50', top: 100, left: 400),
        _line('2', top: 140, left: 10),
        _line('PAN BIMBO', top: 140, left: 150),
        _line('52.00', top: 140, left: 400),
      ]);

      expect(table.columnCount, 3);
      expect(table.cells[1], ['6', 'COCA COLA', '18.50']);
      expect(table.cells[2], ['2', 'PAN BIMBO', '52.00']);
      // La celda ancha se acomoda en la primera columna que toca.
      expect(table.cells[0].where((c) => c.isNotEmpty).single,
          'ABARROTES LOPEZ S.A. DE C.V.');
    });
  });
}
