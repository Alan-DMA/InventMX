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
}
