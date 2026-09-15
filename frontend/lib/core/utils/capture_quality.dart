import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'ocr_helper.dart';

/// Qué le falta a la toma para que valga la pena disparar el obturador.
///
/// El orden importa: se reporta **un solo** problema a la vez, el primero que
/// bloquea, para no abrumar al usuario con tres avisos simultáneos mientras
/// mueve el teléfono frente al repartidor.
enum CaptureIssue {
  /// No hay luz suficiente para que el OCR distinga los caracteres.
  tooDark,

  /// No se ve texto: la cámara no está apuntando a la factura.
  noText,

  /// Hay texto, pero ocupa muy poco del cuadro — la hoja está lejos.
  tooFar,

  /// La hoja está torcida respecto al encuadre.
  tilted,

  /// Nada que corregir.
  none,
}

/// Resultado de evaluar un cuadro de la cámara en vivo.
class CaptureAssessment {
  const CaptureAssessment({
    required this.issue,
    required this.meanLuma,
    required this.coverage,
    this.tiltDegrees,
  });

  const CaptureAssessment.noSignal()
      : issue = CaptureIssue.noText,
        meanLuma = 0,
        coverage = 0,
        tiltDegrees = null;

  final CaptureIssue issue;

  /// Luminancia media del cuadro, 0–255.
  final double meanLuma;

  /// Qué fracción del cuadro (ancho o alto, la mayor) ocupa el texto, 0–1.
  final double coverage;

  /// Inclinación media de las líneas en grados; nulo si ML Kit no la reporta.
  final double? tiltDegrees;

  bool get isReady => issue == CaptureIssue.none;

  /// Instrucción concreta, no diagnóstico: el usuario está de pie frente al
  /// repartidor y necesita saber qué mover, no qué falló.
  String get message => switch (issue) {
        CaptureIssue.tooDark =>
          'Falta luz — enciende la linterna o acércate a una lámpara',
        CaptureIssue.noText => 'Apunta a la tabla de productos de la factura',
        CaptureIssue.tooFar => 'Acerca más la cámara a la factura',
        CaptureIssue.tilted => 'Endereza la factura',
        CaptureIssue.none => 'Listo — ya se puede tomar la foto',
      };
}

/// Umbrales de la evaluación. Se exponen para poder calibrarlos en campo sin
/// tocar la lógica.
///
/// Calibración Q-02 (QA en dispositivo, Sep 2026): Eduardo casi nunca lograba
/// el verde y disparaba con "Tomar de todos modos". Criterio de producto
/// fijado en 12.2.1: el filtro orienta, no bloquea — "listo" es la norma y la
/// advertencia la excepción. Se relajaron los tres umbrales continuos y se
/// corrigió la cobertura (antes se medía contra el ancho del sensor en
/// horizontal aunque las cajas vinieran en vertical: el máximo posible era
/// ~0.56 y el 0.35 exigido equivalía a pegar la hoja al lente).
class CaptureThresholds {
  const CaptureThresholds({
    this.minMeanLuma = 45,
    this.minLineCount = 2,
    this.minCoverage = 0.25,
    this.maxTiltDegrees = 12,
  });

  /// Por debajo de esto el OCR empieza a confundir caracteres en papel térmico.
  final double minMeanLuma;

  /// Una sola palabra suelta no es una factura.
  final int minLineCount;

  /// Fracción mínima del cuadro (ancho **o** alto, la mayor) cubierta por
  /// texto — un ticket angosto llena el alto, una orden apaisada el ancho.
  final double minCoverage;

  final double maxTiltDegrees;
}

/// Evalúa un cuadro en vivo: ¿esta foto se va a poder leer?
///
/// En vez de detectar bordes del documento —que exigiría una librería de visión
/// por computadora y solo aproxima el problema real— se comprueba directamente
/// lo que importa: que haya luz, que el OCR **ya esté leyendo texto**, que ese
/// texto llene el cuadro y que no esté torcido. Es el mismo motor que procesará
/// la foto final, así que lo que aquí se ve es lo que allá se obtendrá.
CaptureAssessment assessCapture({
  required double meanLuma,
  required List<OcrLine> lines,
  required Size frameSize,
  CaptureThresholds thresholds = const CaptureThresholds(),
}) {
  if (meanLuma < thresholds.minMeanLuma) {
    return CaptureAssessment(
      issue: CaptureIssue.tooDark,
      meanLuma: meanLuma,
      coverage: 0,
    );
  }

  if (lines.length < thresholds.minLineCount) {
    return CaptureAssessment(
      issue: CaptureIssue.noText,
      meanLuma: meanLuma,
      coverage: 0,
    );
  }

  final coverage = _textCoverage(lines, frameSize);
  if (coverage < thresholds.minCoverage) {
    return CaptureAssessment(
      issue: CaptureIssue.tooFar,
      meanLuma: meanLuma,
      coverage: coverage,
    );
  }

  final tilt = _meanTilt(lines);
  if (tilt != null && tilt > thresholds.maxTiltDegrees) {
    return CaptureAssessment(
      issue: CaptureIssue.tilted,
      meanLuma: meanLuma,
      coverage: coverage,
      tiltDegrees: tilt,
    );
  }

  return CaptureAssessment(
    issue: CaptureIssue.none,
    meanLuma: meanLuma,
    coverage: coverage,
    tiltDegrees: tilt,
  );
}

/// Unión de todas las cajas de texto como fracción del cuadro — la mayor
/// entre ancho y alto, para que un ticket angosto y alto cuente igual que
/// una orden de compra ancha.
double _textCoverage(List<OcrLine> lines, Size frameSize) {
  if (lines.isEmpty || frameSize.width <= 0 || frameSize.height <= 0) {
    return 0;
  }

  var left = double.infinity;
  var right = double.negativeInfinity;
  var top = double.infinity;
  var bottom = double.negativeInfinity;
  for (final line in lines) {
    left = math.min(left, line.boundingBox.left);
    right = math.max(right, line.boundingBox.right);
    top = math.min(top, line.boundingBox.top);
    bottom = math.max(bottom, line.boundingBox.bottom);
  }

  final horizontal = (right - left) / frameSize.width;
  final vertical = (bottom - top) / frameSize.height;
  return math.max(horizontal, vertical).clamp(0.0, 1.0);
}

/// Inclinación media absoluta; nula si ML Kit no reportó ángulo en ninguna
/// línea (pasa en algunas versiones y en iOS).
double? _meanTilt(List<OcrLine> lines) {
  final angles = [
    for (final line in lines)
      if (line.angle != null) line.angle!.abs(),
  ];
  if (angles.isEmpty) return null;
  return angles.reduce((a, b) => a + b) / angles.length;
}

/// Luminancia media del plano Y de un cuadro YUV420.
///
/// Se muestrea uno de cada [sampleStride] bytes: recorrer el plano completo de
/// un cuadro de 1080p en cada frame tira los FPS en los teléfonos de gama baja
/// que son el objetivo del proyecto. El paso es primo para no caer siempre en
/// la misma columna de la imagen.
double meanLumaFromYPlane(Uint8List yPlane, {int sampleStride = 17}) {
  if (yPlane.isEmpty) return 0;

  var sum = 0;
  var count = 0;
  for (var i = 0; i < yPlane.length; i += sampleStride) {
    sum += yPlane[i];
    count++;
  }
  return count == 0 ? 0 : sum / count;
}

/// Exige que la toma esté bien varios cuadros seguidos antes de habilitar el
/// disparo — y, una vez en verde, tolera un cuadro malo aislado.
///
/// Sin la racha, un cuadro afortunado mientras el usuario mueve el teléfono
/// encendería el botón en verde por un instante. Sin la tolerancia (Q-02),
/// el temblor de la mano lo apagaba justo al tocarlo: a 400 ms por cuadro,
/// un solo cuadro borroso reiniciaba la racha completa.
class CaptureReadinessTracker {
  CaptureReadinessTracker({this.requiredStreak = 2, this.toleratedMisses = 1});

  /// Cuadros buenos seguidos para encender el verde. Dos a 400 ms = 0.8 s
  /// de estabilidad, suficiente para descartar un barrido de la cámara.
  final int requiredStreak;

  /// Cuadros malos seguidos que se perdonan **ya estando en verde**. Antes
  /// de llegar al verde no se perdona ninguno.
  final int toleratedMisses;

  int _streak = 0;
  int _misses = 0;

  int get streak => _streak;
  bool get isStable => _streak >= requiredStreak;

  /// Registra la evaluación de un cuadro y devuelve si ya es estable.
  bool update(CaptureAssessment assessment) {
    if (assessment.isReady) {
      _streak++;
      _misses = 0;
    } else if (isStable && _misses < toleratedMisses) {
      _misses++;
    } else {
      _streak = 0;
      _misses = 0;
    }
    return isStable;
  }

  void reset() {
    _streak = 0;
    _misses = 0;
  }
}
