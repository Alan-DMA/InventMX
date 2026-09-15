import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/utils/ocr_helper.dart';
import 'package:nexus_app/features/purchases/data/receipt_reader.dart';
import 'package:nexus_app/features/purchases/domain/receipt_scan.dart';

/// Reconocedor falso: un juego de líneas por ruta.
class _FakeRecognizer implements OcrTextRecognizer {
  _FakeRecognizer(this.pages);

  final Map<String, List<OcrLine>> pages;
  final calls = <String>[];

  @override
  Future<List<OcrLine>> recognizeLines(String imagePath) async {
    calls.add(imagePath);
    return pages[imagePath] ?? const [];
  }

  @override
  Future<void> dispose() async {}
}

OcrLine _at(String text, double x, double y) => OcrLine(
      text: text,
      boundingBox: Rect.fromCenter(center: Offset(x, y), width: 80, height: 20),
    );

void main() {
  group('ReceiptReader — región del marco (Q-01)', () {
    test('descarta las líneas fuera del marco cuando se conoce el tamaño', () {
      final recognizer = _FakeRecognizer({
        'foto.jpg': [
          _at('Tel. 55 1234 5678', 500, 100),
          _at('COCA COLA', 500, 1000),
          _at('GRACIAS', 500, 1950),
        ],
      });
      final reader = ReceiptReader(
        recognizer: recognizer,
        readSize: (_) async => const Size(1000, 2000),
      );

      final lines = reader.read(ReceiptCapture.single(
        'foto.jpg',
        region: const Rect.fromLTRB(0.1, 0.25, 0.9, 0.75),
      ));

      expect(lines, completion(hasLength(1)));
    });

    test('sin tamaño de imagen lee todo — el recorte nunca bloquea', () async {
      final recognizer = _FakeRecognizer({
        'foto.jpg': [_at('A', 500, 100), _at('B', 500, 1000)],
      });
      final reader = ReceiptReader(
        recognizer: recognizer,
        readSize: (_) async => null,
      );

      final lines = await reader.read(ReceiptCapture.single(
        'foto.jpg',
        region: const Rect.fromLTRB(0.1, 0.25, 0.9, 0.75),
      ));

      expect(lines, hasLength(2));
    });

    test('sin región (archivo) lee todo', () async {
      final recognizer = _FakeRecognizer({
        'foto.jpg': [_at('A', 500, 100), _at('B', 500, 1000)],
      });
      final reader = ReceiptReader(
        recognizer: recognizer,
        readSize: (_) async => const Size(1000, 2000),
      );

      final lines = await reader.read(ReceiptCapture.single('foto.jpg'));

      expect(lines, hasLength(2));
    });

    test('la foto girada por EXIF se resuelve con las cajas', () async {
      // El archivo reporta 2000×1000 (apaisado), pero ML Kit devuelve cajas
      // en el espacio derecho 1000×2000: una caja en y = 1500 no cabe en
      // 1000 de alto, así que el espacio real es el girado.
      final recognizer = _FakeRecognizer({
        'foto.jpg': [_at('arriba', 500, 100), _at('dentro', 500, 1500)],
      });
      final reader = ReceiptReader(
        recognizer: recognizer,
        readSize: (_) async => const Size(2000, 1000),
      );

      final lines = await reader.read(ReceiptCapture.single(
        'foto.jpg',
        region: const Rect.fromLTRB(0, 0.5, 1, 1),
      ));

      expect(lines.map((l) => l.text), ['dentro']);
    });
  });

  group('ReceiptReader — varias páginas (Q-03)', () {
    test('apila las páginas desplazando las cajas hacia abajo', () async {
      final recognizer = _FakeRecognizer({
        'p1.jpg': [_at('COCA COLA', 200, 900), _at('18.50', 600, 900)],
        'p2.jpg': [_at('PAN BIMBO', 200, 100), _at('52.00', 600, 100)],
      });
      final reader = ReceiptReader(
        recognizer: recognizer,
        readSize: (_) async => const Size(1000, 1000),
      );

      final lines = await reader.read(
        const ReceiptCapture(imagePaths: ['p1.jpg', 'p2.jpg']),
      );

      expect(recognizer.calls, ['p1.jpg', 'p2.jpg']);
      expect(lines, hasLength(4));
      // La segunda página empieza debajo de la primera (1000 px + 5 % de
      // separación), así que sus filas no se mezclan con la última de la
      // primera.
      final pan = lines.firstWhere((l) => l.text == 'PAN BIMBO');
      expect(pan.boundingBox.center.dy, closeTo(1050 + 100, 1e-6));
      // Mismas columnas en ambas páginas → una sola tabla.
      final table = detectTable(lines);
      expect(table.cells, [
        ['COCA COLA', '18.50'],
        ['PAN BIMBO', '52.00'],
      ]);
    });

    test('sin tamaño de página apila por el alto ocupado por el texto',
        () async {
      final recognizer = _FakeRecognizer({
        'p1.jpg': [_at('A', 200, 500)],
        'p2.jpg': [_at('B', 200, 100)],
      });
      final reader = ReceiptReader(
        recognizer: recognizer,
        readSize: (_) async => null,
      );

      final lines = await reader.read(
        const ReceiptCapture(imagePaths: ['p1.jpg', 'p2.jpg']),
      );

      final b = lines.firstWhere((l) => l.text == 'B');
      // La página 1 ocupa hasta y = 510; B queda debajo de eso.
      expect(b.boundingBox.top, greaterThan(510));
    });
  });
}
