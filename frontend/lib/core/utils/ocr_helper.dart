import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Una línea de texto reconocida por el OCR, con su caja delimitadora.
///
/// La caja es lo que permite reconstruir las filas visuales de una factura:
/// ML Kit devuelve bloques por zona de la imagen, así que la cantidad, la
/// descripción y el importe de un mismo renglón suelen llegar en bloques
/// distintos y solo la geometría los vuelve a unir.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.boundingBox,
    this.confidence,
    this.angle,
  });

  final String text;
  final Rect boundingBox;
  final double? confidence;

  /// Rotación de la línea en grados según ML Kit — sirve para saber si la
  /// hoja está chueca antes de disparar la foto. Puede venir nula.
  final double? angle;

  double get centerY => boundingBox.center.dy;
  double get left => boundingBox.left;
  double get height => boundingBox.height;

  @override
  String toString() => 'OcrLine("$text", $boundingBox)';
}

/// Contrato de reconocimiento de texto — permite inyectar un doble en tests
/// (ML Kit vive detrás de un canal de plataforma y no corre en `flutter test`).
abstract interface class OcrTextRecognizer {
  /// Extrae las líneas de texto de la imagen en [imagePath].
  Future<List<OcrLine>> recognizeLines(String imagePath);

  Future<void> dispose();
}

/// Implementación real: Google ML Kit Text Recognition, 100% en el dispositivo.
///
/// Constitución Art. II (2.1) y Art. VII (7.7): sin APIs cloud de visión de
/// pago; el procesamiento ocurre en el procesador del teléfono, offline y a
/// costo $0 de servidor.
class MlKitOcrTextRecognizer implements OcrTextRecognizer {
  MlKitOcrTextRecognizer({TextRecognizer? recognizer})
      : _recognizer =
            recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  @override
  Future<List<OcrLine>> recognizeLines(String imagePath) async {
    final recognized =
        await _recognizer.processImage(InputImage.fromFilePath(imagePath));

    return [
      for (final block in recognized.blocks)
        for (final line in block.lines)
          OcrLine(
            text: line.text,
            boundingBox: line.boundingBox,
            confidence: line.confidence,
            angle: line.angle,
          ),
    ];
  }

  @override
  Future<void> dispose() => _recognizer.close();
}

/// Reagrupa las líneas sueltas del OCR en filas visuales.
///
/// Dos líneas pertenecen a la misma fila si sus centros verticales están más
/// cerca que [toleranceFactor] veces la altura de la línea — la tolerancia es
/// relativa (no un número fijo de píxeles) para que funcione igual con una
/// foto de 1080p que con una de 4K.
List<String> groupLinesIntoRows(
  List<OcrLine> lines, {
  double toleranceFactor = 0.6,
}) {
  if (lines.isEmpty) return const [];

  final sorted = [...lines]..sort((a, b) => a.centerY.compareTo(b.centerY));

  final rows = <List<OcrLine>>[];
  var current = <OcrLine>[sorted.first];

  for (final line in sorted.skip(1)) {
    final reference = current.last;
    final tolerance = reference.height * toleranceFactor;
    if ((line.centerY - reference.centerY).abs() <= tolerance) {
      current.add(line);
    } else {
      rows.add(current);
      current = [line];
    }
  }
  rows.add(current);

  return [
    for (final row in rows)
      (row..sort((a, b) => a.left.compareTo(b.left)))
          .map((l) => l.text.trim())
          .where((t) => t.isNotEmpty)
          .join(' '),
  ].where((row) => row.isNotEmpty).toList();
}
