import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/utils/capture_quality.dart';
import 'package:nexus_app/core/utils/ocr_helper.dart';

const _frame = Size(1080, 1920);

/// Líneas que cubren [coverage] del ancho del cuadro.
List<OcrLine> _lines({
  int count = 4,
  double coverage = 0.7,
  double? angle = 0,
}) {
  final width = _frame.width * coverage;
  return [
    for (var i = 0; i < count; i++)
      OcrLine(
        text: 'RENGLON $i',
        boundingBox: Rect.fromLTWH(100, 200 + i * 40, width, 24),
        angle: angle,
      ),
  ];
}

void main() {
  group('assessCapture', () {
    test('la falta de luz bloquea antes que cualquier otra revisión', () {
      final result = assessCapture(
        meanLuma: 30,
        lines: _lines(),
        frameSize: _frame,
      );

      expect(result.issue, CaptureIssue.tooDark);
      expect(result.isReady, isFalse);
      expect(result.message, contains('linterna'));
    });

    test('sin texto suficiente pide apuntar a la factura', () {
      final result = assessCapture(
        meanLuma: 120,
        lines: _lines(count: 1),
        frameSize: _frame,
      );

      expect(result.issue, CaptureIssue.noText);
    });

    test('texto pequeño en el cuadro se lee como "estás lejos"', () {
      final result = assessCapture(
        meanLuma: 120,
        lines: _lines(coverage: 0.15),
        frameSize: _frame,
      );

      expect(result.issue, CaptureIssue.tooFar);
      expect(result.coverage, closeTo(0.15, 0.01));
    });

    test('un ticket angosto que llena el alto del cuadro no está lejos (Q-02)',
        () {
      // 30 % del ancho, pero 80 % del alto: cobertura = la mayor.
      final lines = [
        for (var i = 0; i < 20; i++)
          OcrLine(
            text: 'RENGLON ',
            boundingBox: Rect.fromLTWH(380, 200 + i * 76, 320, 24),
            angle: 0,
          ),
      ];
      final result = assessCapture(
        meanLuma: 120,
        lines: lines,
        frameSize: _frame,
      );

      expect(result.issue, CaptureIssue.none);
      expect(result.coverage, greaterThan(0.7));
    });

    test('una hoja torcida pide enderezarla', () {
      final result = assessCapture(
        meanLuma: 120,
        lines: _lines(angle: 14),
        frameSize: _frame,
      );

      expect(result.issue, CaptureIssue.tilted);
      expect(result.tiltDegrees, closeTo(14, 0.01));
    });

    test('una inclinación leve no bloquea el disparo', () {
      final result = assessCapture(
        meanLuma: 120,
        lines: _lines(angle: 3),
        frameSize: _frame,
      );

      expect(result.isReady, isTrue);
    });

    test('la inclinación negativa cuenta igual que la positiva', () {
      final result = assessCapture(
        meanLuma: 120,
        lines: _lines(angle: -14),
        frameSize: _frame,
      );

      expect(result.issue, CaptureIssue.tilted);
    });

    test('si ML Kit no reporta ángulo, no se bloquea por inclinación', () {
      final result = assessCapture(
        meanLuma: 120,
        lines: _lines(angle: null),
        frameSize: _frame,
      );

      expect(result.isReady, isTrue);
      expect(result.tiltDegrees, isNull);
    });

    test('con luz, texto, encuadre y hoja derecha la toma está lista', () {
      final result = assessCapture(
        meanLuma: 140,
        lines: _lines(),
        frameSize: _frame,
      );

      expect(result.isReady, isTrue);
      expect(result.message, contains('Listo'));
    });

    test('los umbrales se pueden calibrar sin tocar la lógica', () {
      const strict = CaptureThresholds(minMeanLuma: 200);
      final result = assessCapture(
        meanLuma: 140,
        lines: _lines(),
        frameSize: _frame,
        thresholds: strict,
      );

      expect(result.issue, CaptureIssue.tooDark);
    });
  });

  group('meanLumaFromYPlane', () {
    test('promedia el plano de luminancia', () {
      final plane = Uint8List.fromList(List.filled(1000, 80));

      expect(meanLumaFromYPlane(plane), closeTo(80, 0.001));
    });

    test('un plano vacío devuelve cero en vez de dividir entre cero', () {
      expect(meanLumaFromYPlane(Uint8List(0)), 0);
    });

    test('el muestreo no altera el promedio de un plano uniforme', () {
      final plane = Uint8List.fromList(List.filled(5000, 200));

      expect(meanLumaFromYPlane(plane, sampleStride: 97), closeTo(200, 0.001));
    });
  });

  group('CaptureReadinessTracker', () {
    const ready = CaptureAssessment(
      issue: CaptureIssue.none,
      meanLuma: 140,
      coverage: 0.7,
    );
    const dark = CaptureAssessment(
      issue: CaptureIssue.tooDark,
      meanLuma: 20,
      coverage: 0,
    );

    test('un solo cuadro bueno no habilita el disparo', () {
      final tracker = CaptureReadinessTracker();

      expect(tracker.update(ready), isFalse);
      expect(tracker.isStable, isFalse);
    });

    test('dos cuadros buenos seguidos sí lo habilitan (Q-02)', () {
      final tracker = CaptureReadinessTracker();

      tracker.update(ready);

      expect(tracker.update(ready), isTrue);
    });

    test('antes del verde, un cuadro malo reinicia la racha', () {
      final tracker = CaptureReadinessTracker(requiredStreak: 3);

      tracker.update(ready);
      tracker.update(ready);
      tracker.update(dark);

      expect(tracker.isStable, isFalse);
      expect(tracker.streak, 0);
    });

    test('ya en verde, un cuadro malo aislado no apaga el disparo (Q-02)', () {
      final tracker = CaptureReadinessTracker();

      tracker.update(ready);
      tracker.update(ready);

      expect(tracker.update(dark), isTrue);
      expect(tracker.update(ready), isTrue);
    });

    test('ya en verde, dos cuadros malos seguidos sí lo apagan', () {
      final tracker = CaptureReadinessTracker();

      tracker.update(ready);
      tracker.update(ready);
      tracker.update(dark);

      expect(tracker.update(dark), isFalse);
      expect(tracker.streak, 0);
    });

    test('reset borra la racha y la tolerancia', () {
      final tracker = CaptureReadinessTracker();

      tracker.update(ready);
      tracker.update(ready);
      tracker.reset();

      expect(tracker.isStable, isFalse);
      expect(tracker.update(dark), isFalse);
    });

    test('la racha requerida es configurable', () {
      final tracker = CaptureReadinessTracker(requiredStreak: 1);

      expect(tracker.update(ready), isTrue);
    });
  });
}
