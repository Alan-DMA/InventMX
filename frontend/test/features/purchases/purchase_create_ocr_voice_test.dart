import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/core/utils/ocr_helper.dart';
import 'package:nexus_app/core/utils/voice_dictation_helper.dart';
import 'package:nexus_app/features/purchases/presentation/purchase_create_screen.dart';
import 'package:nexus_app/features/purchases/presentation/purchases_provider.dart';
import 'package:nexus_app/features/purchases/presentation/receipt_capture_screen.dart';
// ---------------------------------------------------------------------------
// Dobles de las tres capacidades de plataforma — ML Kit, cámara y motor de voz
// viven detrás de canales nativos que no existen en `flutter test`.
// ---------------------------------------------------------------------------
class _FakePhotoSource implements ReceiptPhotoSource {
  _FakePhotoSource({this.path});
  final String? path;
  int calls = 0;
  @override
  Future<String?> capture(BuildContext context) async {
    calls++;
    return path;
  }
}
class _FakeRecognizer implements OcrTextRecognizer {
  _FakeRecognizer(this.rows);
  /// Cada entrada es un renglón visual; se le fabrica una caja propia para
  /// que `groupLinesIntoRows` los mantenga separados.
  final List<String> rows;
  @override
  Future<List<OcrLine>> recognizeLines(String imagePath) async => [
        for (var i = 0; i < rows.length; i++)
          OcrLine(
            text: rows[i],
            boundingBox: Rect.fromLTWH(10, 100.0 * (i + 1), 300, 20),
          ),
      ];
  @override
  Future<void> dispose() async {}
}
class _FakeVoiceService implements VoiceDictationService {
  _FakeVoiceService({this.transcript = '', this.available = true});
  final String transcript;
  final bool available;
  @override
  bool isListening = false;
  @override
  Future<bool> initialize() async => available;
  @override
  Future<void> listen({
    required void Function(String transcript, bool isFinal) onResult,
  }) async {
    isListening = true;
    onResult(transcript, true);
    isListening = false;
  }
  @override
  Future<void> stop() async => isListening = false;
  @override
  void dispose() {}
}
// ---------------------------------------------------------------------------
void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
Future<void> _pumpReady(
  WidgetTester tester, {
  ReceiptPhotoSource? photoSource,
  OcrTextRecognizer? recognizer,
  VoiceDictationService? voice,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (photoSource != null)
          receiptPhotoSourceProvider.overrideWithValue(photoSource),
        if (recognizer != null)
          ocrTextRecognizerProvider.overrideWithValue(recognizer),
        if (voice != null)
          voiceDictationServiceProvider.overrideWithValue(voice),
      ],
      child:
          MaterialApp(theme: AppTheme.dark, home: const PurchaseCreateScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}
void main() {
  group('escaneo de factura (12.2.1 / 12.2.2)', () {
    testWidgets('la factura leída llega a la orden tras revisarla',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(
        tester,
        photoSource: _FakePhotoSource(path: 'factura.jpg'),
        recognizer: _FakeRecognizer([
          'DISTRIBUIDORA BIMBO NORTE',
          'CANTIDAD DESCRIPCION PRECIO IMPORTE',
          '6 COCA COLA 600ML 18.50 111.00',
          r'2 PZ PAN BIMBO GDE $52.00 $104.00',
          'TOTAL 215.00',
        ]),
      );
      await tester.tap(find.byKey(const Key('scanReceiptButton')));
      await tester.pumpAndSettle();
      // Pantalla de revisión con lo detectado y el cuadre contra la factura.
      expect(find.text('2 productos detectados'), findsOneWidget);
      expect(
        find.textContaining('Cuadra con el total impreso'),
        findsOneWidget,
      );
      await tester.tap(find.text('Agregar 2 productos a la orden'));
      await tester.pumpAndSettle();
      // De vuelta en la orden, con las dos líneas ya cargadas.
      expect(find.text('Nueva orden de compra'), findsOneWidget);
      expect(find.text('COCA COLA 600ML'), findsOneWidget);
      expect(find.text('PAN BIMBO GDE'), findsOneWidget);
      expect(find.text('\$215.00 MXN'), findsOneWidget);
    });
    testWidgets('cancelar la cámara deja la orden intacta', (tester) async {
      _setPhoneViewport(tester);
      final source = _FakePhotoSource(); // El usuario cierra la cámara.
      await _pumpReady(tester, photoSource: source);
      await tester.tap(find.byKey(const Key('scanReceiptButton')));
      await tester.pumpAndSettle();
      expect(source.calls, 1);
      expect(find.text('Aún no agregas productos a esta orden.'),
          findsOneWidget);
    });
    testWidgets('una foto ilegible explica cómo repetirla', (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(
        tester,
        photoSource: _FakePhotoSource(path: 'borrosa.jpg'),
        recognizer: _FakeRecognizer(const []),
      );
      await tester.tap(find.byKey(const Key('scanReceiptButton')));
      await tester.pumpAndSettle();
      expect(find.text('No se reconocieron productos'), findsOneWidget);
      expect(find.text('Capturar a mano'), findsOneWidget);
    });
  });
  group('dictado de voz (12.2.3 / SR-09)', () {
    testWidgets('rellena nombre, cantidad y costo de un solo dictado',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(
        tester,
        voice: _FakeVoiceService(
          transcript: 'Maruchan Pollo, precio 16, 36 piezas',
        ),
      );
      await tester.tap(find.byKey(const Key('dictationButton')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
                find.byKey(const Key('purchaseEntryNameField')))
            .controller
            ?.text,
        'Maruchan Pollo',
      );
      expect(
        tester
            .widget<TextFormField>(
                find.byKey(const Key('purchaseEntryQtyField')))
            .controller
            ?.text,
        '36',
      );
      expect(
        tester
            .widget<TextFormField>(
                find.byKey(const Key('purchaseEntryCostField')))
            .controller
            ?.text,
        '16.00',
      );
    });
    testWidgets('lo dictado queda listo para agregarse a la orden',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(
        tester,
        voice: _FakeVoiceService(
          transcript: 'Coca-Cola 600, precio 18, 24 piezas',
        ),
      );
      await tester.tap(find.byKey(const Key('dictationButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
      await tester.pumpAndSettle();
      expect(find.text('Coca-Cola 600'), findsOneWidget);
      expect(find.textContaining('24'), findsWidgets);
    });
    testWidgets('sin micrófono disponible avisa cómo resolverlo',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(tester, voice: _FakeVoiceService(available: false));
      await tester.tap(find.byKey(const Key('dictationButton')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('El dictado no está disponible'),
        findsOneWidget,
      );
    });
    testWidgets('un dictado que no se entiende no inventa valores',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(tester, voice: _FakeVoiceService(transcript: ''));
      await tester.tap(find.byKey(const Key('dictationButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se entendió'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
                find.byKey(const Key('purchaseEntryNameField')))
            .controller
            ?.text,
        isEmpty,
      );
    });
  });
}
