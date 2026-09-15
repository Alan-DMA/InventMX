import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'capture_quality.dart';
import 'ocr_helper.dart';

/// Evalúa cuadros de la cámara en vivo para decidir si ya se puede disparar.
///
/// Contrato aparte de [OcrTextRecognizer] a propósito: ese lee un archivo ya
/// guardado; este consume el stream y arrastra tipos del paquete `camera`.
/// Separarlos evita que la lectura de la foto final dependa de la cámara.
abstract interface class CaptureFrameAnalyzer {
  Future<CaptureAssessment> analyze(CameraImage frame, int sensorOrientation);

  Future<void> dispose();
}

/// Implementación real: luminancia del plano Y + ML Kit sobre el cuadro vivo.
///
/// Es el mismo motor de OCR que procesará la foto final, así que lo que el
/// usuario ve en verde es literalmente "esto ya se puede leer", no una
/// aproximación geométrica de si hay un rectángulo en el encuadre.
class MlKitCaptureFrameAnalyzer implements CaptureFrameAnalyzer {
  MlKitCaptureFrameAnalyzer({
    TextRecognizer? recognizer,
    this.thresholds = const CaptureThresholds(),
  }) : _recognizer =
            recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;
  final CaptureThresholds thresholds;

  @override
  Future<CaptureAssessment> analyze(
    CameraImage frame,
    int sensorOrientation,
  ) async {
    final luma = meanLumaFromYPlane(frame.planes.first.bytes);

    // Sin luz no vale la pena pagar el costo del OCR sobre el cuadro.
    if (luma < thresholds.minMeanLuma) {
      return CaptureAssessment(
        issue: CaptureIssue.tooDark,
        meanLuma: luma,
        coverage: 0,
      );
    }

    final input = _toInputImage(frame, sensorOrientation);
    if (input == null) {
      return CaptureAssessment(
        issue: CaptureIssue.noText,
        meanLuma: luma,
        coverage: 0,
      );
    }

    final recognized = await _recognizer.processImage(input);
    final lines = [
      for (final block in recognized.blocks)
        for (final line in block.lines)
          OcrLine(
            text: line.text,
            boundingBox: line.boundingBox,
            confidence: line.confidence,
            angle: line.angle,
          ),
    ];

    return assessCapture(
      meanLuma: luma,
      lines: lines,
      frameSize: uprightFrameSize(frame.width, frame.height, sensorOrientation),
      thresholds: thresholds,
    );
  }

  /// Tamaño del cuadro en el espacio donde ML Kit devuelve las cajas.
  ///
  /// El sensor entrega el cuadro apaisado (p. ej. 1280×720) y ML Kit, al
  /// recibir la rotación en los metadatos, devuelve las cajas ya en el
  /// cuadro derecho (720×1280). Medir la cobertura contra el ancho del
  /// sensor era el bug de Q-02: con el teléfono en vertical el máximo
  /// alcanzable era 720/1280 ≈ 0.56 y el umbral se volvía casi imposible.
  static Size uprightFrameSize(int width, int height, int sensorOrientation) {
    final rotated = sensorOrientation % 180 != 0;
    return rotated
        ? Size(height.toDouble(), width.toDouble())
        : Size(width.toDouble(), height.toDouble());
  }

  /// Empaqueta el cuadro para ML Kit. Devuelve nulo si el formato del
  /// dispositivo no es uno de los que ML Kit acepta directamente — en ese caso
  /// la pantalla se queda en "apunta a la factura" y el usuario siempre puede
  /// forzar el disparo.
  InputImage? _toInputImage(CameraImage frame, int sensorOrientation) {
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    final format = InputImageFormatValue.fromRawValue(frame.format.raw as int);
    if (rotation == null || format == null) return null;

    final Uint8List bytes;
    if (frame.planes.length == 1) {
      bytes = frame.planes.first.bytes;
    } else {
      final builder = BytesBuilder(copy: false);
      for (final plane in frame.planes) {
        builder.add(plane.bytes);
      }
      bytes = builder.toBytes();
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: frame.planes.first.bytesPerRow,
      ),
    );
  }

  @override
  Future<void> dispose() => _recognizer.close();
}
