import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/core/utils/capture_quality.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/capture_guidance.dart';

Future<void> _pump(
  WidgetTester tester, {
  CaptureAssessment? assessment,
  bool isReady = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: CaptureGuidance(assessment: assessment, isReady: isReady),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('antes del primer cuadro analizado dice que está enfocando',
      (tester) async {
    await _pump(tester);

    expect(find.text('Enfocando la factura…'), findsOneWidget);
  });

  testWidgets('la falta de luz se comunica con la acción que la resuelve',
      (tester) async {
    await _pump(
      tester,
      assessment: const CaptureAssessment(
        issue: CaptureIssue.tooDark,
        meanLuma: 20,
        coverage: 0,
      ),
    );

    expect(find.textContaining('Falta luz'), findsOneWidget);
    expect(find.textContaining('linterna'), findsOneWidget);
  });

  testWidgets('estar lejos pide acercarse, no reporta cobertura',
      (tester) async {
    await _pump(
      tester,
      assessment: const CaptureAssessment(
        issue: CaptureIssue.tooFar,
        meanLuma: 120,
        coverage: 0.12,
      ),
    );

    expect(find.text('Acerca más la cámara a la factura'), findsOneWidget);
    expect(find.textContaining('0.12'), findsNothing);
  });

  testWidgets('la hoja torcida pide enderezarla', (tester) async {
    await _pump(
      tester,
      assessment: const CaptureAssessment(
        issue: CaptureIssue.tilted,
        meanLuma: 120,
        coverage: 0.7,
        tiltDegrees: 15,
      ),
    );

    expect(find.text('Endereza la factura'), findsOneWidget);
  });

  testWidgets('sin texto pide apuntar a la tabla de productos', (tester) async {
    await _pump(tester, assessment: const CaptureAssessment.noSignal());

    expect(find.textContaining('Apunta a la tabla'), findsOneWidget);
  });

  testWidgets('listo cambia el ícono a confirmación', (tester) async {
    await _pump(
      tester,
      assessment: const CaptureAssessment(
        issue: CaptureIssue.none,
        meanLuma: 140,
        coverage: 0.7,
      ),
      isReady: true,
    );

    expect(find.textContaining('Listo'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
  });

  testWidgets('un cuadro bueno pero aún inestable no se muestra como listo',
      (tester) async {
    await _pump(
      tester,
      assessment: const CaptureAssessment(
        issue: CaptureIssue.none,
        meanLuma: 140,
        coverage: 0.7,
      ),
      // El tracker todavía no acumuló la racha.
      isReady: false,
    );

    expect(find.byIcon(Icons.check_circle_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.center_focus_weak_rounded), findsOneWidget);
  });
}
