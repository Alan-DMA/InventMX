import 'dart:math' as math;
import 'dart:ui';

import '../../../core/utils/image_size.dart';
import '../../../core/utils/ocr_helper.dart';
import '../../../core/utils/viewfinder_region.dart';
import '../domain/receipt_scan.dart';

/// Lee un [ReceiptCapture] (foto o páginas de PDF) y devuelve las líneas del
/// OCR como si fueran una sola hoja — Tarea 12.2, Q-01 + Q-03.
///
///   · Foto con región del marco: se descartan las líneas fuera del marco
///     antes de que `detectTable` las vea (Q-01). Así el OCR "solo lee lo que
///     el usuario encuadró" sin recortar ni re-codificar la imagen.
///   · Varias páginas: cada página se apila debajo de la anterior
///     desplazando sus cajas, de modo que las columnas de todas las páginas
///     (mismo formato) caen en las mismas columnas de una sola tabla y el
///     mapeo se hace una vez (Q-03).
class ReceiptReader {
  const ReceiptReader({
    required this.recognizer,
    this.readSize = readImageSize,
  });

  final OcrTextRecognizer recognizer;

  /// Inyectable: en tests no hay archivos reales.
  final Future<Size?> Function(String path) readSize;

  /// Separación entre páginas apiladas, como fracción del alto de la página
  /// — evita que la última fila de una página y la primera de la siguiente
  /// caigan en el mismo renglón.
  static const double _pageGapFraction = 0.05;

  Future<List<OcrLine>> read(ReceiptCapture capture) async {
    final all = <OcrLine>[];
    var offsetY = 0.0;

    for (final path in capture.imagePaths) {
      var lines = await recognizer.recognizeLines(path);
      final decoded = await readSize(path);
      final space = decoded == null
          ? null
          : resolveImageSpace(
              decoded,
              lines,
              portraitViewport: capture.portraitViewport,
            );

      final region = capture.region;
      if (region != null && space != null) {
        lines = clipLinesToRegion(lines, region, space);
      }

      if (offsetY > 0) {
        lines = [for (final line in lines) _shifted(line, offsetY)];
      }
      all.addAll(lines);

      final pageHeight = space?.height ?? _extentOf(lines, offsetY);
      offsetY += pageHeight * (1 + _pageGapFraction);
    }
    return all;
  }

  static OcrLine _shifted(OcrLine line, double dy) => OcrLine(
        text: line.text,
        boundingBox: line.boundingBox.shift(Offset(0, dy)),
        confidence: line.confidence,
        angle: line.angle,
        direction: line.direction,
      );

  /// Alto ocupado por las líneas cuando no se pudo leer el tamaño real de
  /// la imagen (ya desplazadas: se descuenta [offsetY]).
  static double _extentOf(List<OcrLine> lines, double offsetY) {
    var bottom = 0.0;
    for (final line in lines) {
      bottom = math.max(bottom, line.boundingBox.bottom - offsetY);
    }
    return bottom;
  }
}
