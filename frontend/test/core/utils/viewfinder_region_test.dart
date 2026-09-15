import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/utils/ocr_helper.dart';
import 'package:nexus_app/core/utils/viewfinder_region.dart';

OcrLine _at(String text, double x, double y) => OcrLine(
      text: text,
      boundingBox: Rect.fromCenter(center: Offset(x, y), width: 80, height: 20),
    );

void main() {
  group('viewfinderRegion (Q-01)', () {
    test('vista previa del mismo aspecto que el visor: el marco se mapea '
        'directo', () {
      // Visor 400×800 (1:2), preview 1:2 → sin recorte lateral.
      final region = viewfinderRegion(
        viewport: const Size(400, 800),
        frame: const Size(200, 400),
        previewAspect: 0.5,
        margin: 0,
      );

      expect(region.left, closeTo(0.25, 1e-6));
      expect(region.top, closeTo(0.25, 1e-6));
      expect(region.right, closeTo(0.75, 1e-6));
      expect(region.bottom, closeTo(0.75, 1e-6));
    });

    test('preview más ancha que el visor (cover): se descuenta lo recortado '
        'a los lados', () {
      // Visor 400×800; preview 3:4 en vertical (0.75) escalada a cubrir el
      // alto: 600×800, con 100 px recortados por cada lado.
      final region = viewfinderRegion(
        viewport: const Size(400, 800),
        frame: const Size(200, 400),
        previewAspect: 0.75,
        margin: 0,
      );

      // Marco en el visor: x 100..300 → en la preview 200..400 de 600.
      expect(region.left, closeTo(200 / 600, 1e-6));
      expect(region.right, closeTo(400 / 600, 1e-6));
      expect(region.top, closeTo(0.25, 1e-6));
      expect(region.bottom, closeTo(0.75, 1e-6));
    });

    test('preview más alta que el visor: se descuenta lo recortado arriba y '
        'abajo', () {
      // Visor 400×600; preview 1:2 escalada a cubrir el ancho: 400×800,
      // con 100 px recortados arriba y abajo.
      final region = viewfinderRegion(
        viewport: const Size(400, 600),
        frame: const Size(200, 300),
        previewAspect: 0.5,
        margin: 0,
      );

      expect(region.left, closeTo(0.25, 1e-6));
      expect(region.right, closeTo(0.75, 1e-6));
      // Marco en el visor: y 150..450 → en la preview 250..550 de 800.
      expect(region.top, closeTo(250 / 800, 1e-6));
      expect(region.bottom, closeTo(550 / 800, 1e-6));
    });

    test('el margen amplía el marco y nunca sale de la imagen', () {
      final region = viewfinderRegion(
        viewport: const Size(400, 800),
        frame: const Size(400, 800),
        previewAspect: 0.5,
        margin: 0.1,
      );

      expect(region, const Rect.fromLTRB(0, 0, 1, 1));
    });

    test('con un visor sin tamaño se lee la imagen completa', () {
      expect(
        viewfinderRegion(
          viewport: Size.zero,
          frame: const Size(200, 400),
          previewAspect: 0.5,
        ),
        const Rect.fromLTRB(0, 0, 1, 1),
      );
    });
  });

  group('resolveImageSpace', () {
    test('si las cajas no caben en el tamaño reportado pero sí girado, gira',
        () {
      final space = resolveImageSpace(
        const Size(4000, 3000),
        [_at('x', 2900, 3900)],
        portraitViewport: true,
      );

      expect(space, const Size(3000, 4000));
    });

    test('sin cajas decide por la orientación del visor', () {
      expect(
        resolveImageSpace(const Size(4000, 3000), const [],
            portraitViewport: true),
        const Size(3000, 4000),
      );
      expect(
        resolveImageSpace(const Size(4000, 3000), const [],
            portraitViewport: false),
        const Size(4000, 3000),
      );
    });

    test('si las cajas caben solo en el tamaño reportado, lo conserva', () {
      final space = resolveImageSpace(
        const Size(4000, 3000),
        [_at('x', 3900, 100)],
        portraitViewport: true,
      );

      expect(space, const Size(4000, 3000));
    });
  });

  group('clipLinesToRegion', () {
    final lines = [
      _at('RFC arriba', 500, 100),
      _at('COCA COLA', 500, 1000),
      _at('18.50', 900, 1000),
      _at('GRACIAS abajo', 500, 1900),
      _at('fuera a la izquierda', 20, 1000),
    ];

    test('conserva solo las líneas cuyo centro cae dentro del marco', () {
      final kept = clipLinesToRegion(
        lines,
        const Rect.fromLTRB(0.1, 0.25, 0.95, 0.75),
        const Size(1000, 2000),
      );

      expect(kept.map((l) => l.text), ['COCA COLA', '18.50']);
    });

    test('la región completa devuelve todo sin tocar', () {
      final kept = clipLinesToRegion(
        lines,
        const Rect.fromLTWH(0, 0, 1, 1),
        const Size(1000, 2000),
      );

      expect(identical(kept, lines), isTrue);
    });
  });
}
