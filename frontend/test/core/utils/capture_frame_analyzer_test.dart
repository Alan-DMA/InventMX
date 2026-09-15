import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/utils/capture_frame_analyzer.dart';

void main() {
  group('MlKitCaptureFrameAnalyzer.uprightFrameSize (Q-02)', () {
    test('con el sensor a 90° o 270° las cajas vienen en el cuadro derecho',
        () {
      expect(MlKitCaptureFrameAnalyzer.uprightFrameSize(1280, 720, 90),
          const Size(720, 1280));
      expect(MlKitCaptureFrameAnalyzer.uprightFrameSize(1280, 720, 270),
          const Size(720, 1280));
    });

    test('a 0° o 180° el cuadro no cambia', () {
      expect(MlKitCaptureFrameAnalyzer.uprightFrameSize(1280, 720, 0),
          const Size(1280, 720));
      expect(MlKitCaptureFrameAnalyzer.uprightFrameSize(1280, 720, 180),
          const Size(1280, 720));
    });
  });
}
