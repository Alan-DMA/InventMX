import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/core/utils/ocr_helper.dart';
import 'package:nexus_app/core/utils/voice_dictation_helper.dart';
import 'package:nexus_app/features/purchases/data/receipt_file_source.dart';
import 'package:nexus_app/features/purchases/data/receipt_mapping_store.dart';
import 'package:nexus_app/features/purchases/domain/receipt_scan.dart';
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
  Future<ReceiptCapture?> capture(BuildContext context) async {
    calls++;
    return path == null ? null : ReceiptCapture.single(path!);
  }
}

/// Selector de archivo falso — Q-03.
class _FakeFileSource implements ReceiptFileSource {
  _FakeFileSource({this.capture});
  final ReceiptCapture? capture;
  int calls = 0;
  @override
  Future<ReceiptCapture?> pick() async {
    calls++;
    return capture;
  }
}

class _FakeRecognizer implements OcrTextRecognizer {
  _FakeRecognizer(this.rows);

  /// Cada entrada es un renglón visual; las celdas van separadas por dos o
  /// más espacios y se colocan en columnas fijas — como ML Kit devuelve
  /// bloques por zona, `detectTable` las vuelve a unir por geometría.
  final List<String> rows;
  @override
  Future<List<OcrLine>> recognizeLines(String imagePath) async => [
        for (var i = 0; i < rows.length; i++)
          for (final (c, cell) in rows[i].split(RegExp(r'\s{2,}')).indexed)
            OcrLine(
              text: cell,
              boundingBox:
                  Rect.fromLTWH(10 + 160.0 * c, 100.0 * (i + 1), 140, 20),
            ),
      ];
  @override
  Future<void> dispose() async {}
}

/// Un segmento por `listen()` (contrato desde la octava iteración: sin
/// reinicio automático). Cada llamada entrega el siguiente segmento de la
/// cola y cierra; si la cola está vacía, el motor queda "escuchando" hasta
/// que el usuario toque Detener (`stop()`) o "hable" (`speak()`).
class _FakeVoiceService implements VoiceDictationService {
  _FakeVoiceService({
    String transcript = '',
    this.available = true,
    this.errorOnFirstCall = false,
    this.prematureEmptyFinal = false,
    this.midSessionRegression = false,
  }) : _queue = [transcript];
  final List<String> _queue;
  final bool available;

  /// Simula un error de plataforma (red, timeout del reconocedor) en la
  /// primera sesión en vez de un resultado — el modal debe quedar en
  /// "detenido" con lo que hubiera, y "Volver a grabar" sí entrega el
  /// transcript (bug real reportado: la escucha quedaba muerta en silencio).
  final bool errorOnFirstCall;

  /// Simula que el motor cierra el segmento con un resultado final VACÍO
  /// después de haber mostrado un parcial con contenido real — bug real
  /// reportado: el parcial ya visto en pantalla se perdía.
  final bool prematureEmptyFinal;

  /// Simula que el motor, a mitad del MISMO segmento, revisa su propia
  /// hipótesis y entrega un parcial más corto antes de cerrar con un final
  /// vacío — bug real reportado (distinto de `prematureEmptyFinal`: ahí el
  /// corte es al final; aquí ocurre mientras sigue "escuchando").
  final bool midSessionRegression;
  int listenCalls = 0;
  void Function(String transcript, bool isFinal)? _onResult;
  void Function()? _onListening;
  @override
  bool isListening = false;
  @override
  Future<bool> initialize() async => available;
  @override
  Future<void> listen({
    required void Function(String transcript, bool isFinal) onResult,
    void Function()? onError,
    void Function()? onListening,
  }) async {
    isListening = true;
    listenCalls++;
    _onResult = onResult;
    _onListening = onListening;
    if (errorOnFirstCall && listenCalls == 1) {
      onError?.call();
      isListening = false;
      return;
    }
    if (_queue.isEmpty) return;
    final transcript = _queue.removeAt(0);
    if (prematureEmptyFinal && listenCalls == 1) {
      onResult(transcript, false);
      onResult('', true);
    } else if (midSessionRegression && listenCalls == 1) {
      onResult(transcript, false);
      // Revisión espuria del motor a mitad de segmento: más corta que lo ya
      // mostrado. `DictationModal` debe ignorarla, no sobreescribir.
      onResult(transcript.split(' ').first, false);
      onResult('', true);
    } else {
      onResult(transcript, true);
    }
    isListening = false;
  }

  /// Encola lo que el motor entregará en el siguiente `listen()`.
  void queue(String segment) => _queue.add(segment);

  /// Simula que el micrófono ya capta audio en la sesión actual (primer
  /// evento de nivel de sonido del motor real).
  void micReady() => _onListening?.call();

  /// Simula que el usuario dice algo durante una sesión abierta: el motor
  /// la cierra con el texto dado.
  void speak(String segment) {
    isListening = false;
    _onResult?.call(segment, true);
  }

  @override
  Future<void> stop() async {
    if (!isListening) return;
    isListening = false;
    _onResult?.call('', true);
  }

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
Future<void> _openAndStartDictation(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('dictationModalOpenButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('dictationModalStartButton')));
  await tester.pumpAndSettle();
}

Future<void> _resumeDictation(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('dictationModalResumeButton')));
  await tester.pumpAndSettle();
}

Future<void> _stopDictation(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('dictationModalStopButton')));
  await tester.pumpAndSettle();
}

Future<void> _submitDictation(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('dictationModalSubmitButton')));
  await tester.pumpAndSettle();
}

String _transcriptFieldText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('dictationModalTranscriptField')))
    .controller!
    .text;
// ---------------------------------------------------------------------------
void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Un juego de renglones por página — Q-03.
class _FakePagedRecognizer implements OcrTextRecognizer {
  _FakePagedRecognizer(this.pages);
  final Map<String, List<String>> pages;
  @override
  Future<List<OcrLine>> recognizeLines(String imagePath) =>
      _FakeRecognizer(pages[imagePath] ?? const []).recognizeLines(imagePath);
  @override
  Future<void> dispose() async {}
}

class _ThrowingFileSource implements ReceiptFileSource {
  @override
  Future<ReceiptCapture?> pick() async => throw StateError('sin selector');
}

/// Mapeos por proveedor en memoria — Hive no está inicializado en
/// `flutter test`.
class _FakeMappingStore implements ReceiptMappingStore {
  final saved = <String, ReceiptColumnMapping>{};
  @override
  Future<ReceiptColumnMapping?> load(String supplier) async =>
      saved[normalizeSupplier(supplier)];
  @override
  Future<void> save(String supplier, ReceiptColumnMapping mapping) async =>
      saved[normalizeSupplier(supplier)] = mapping;
}

Future<void> _pumpReady(
  WidgetTester tester, {
  ReceiptPhotoSource? photoSource,
  ReceiptFileSource? fileSource,
  OcrTextRecognizer? recognizer,
  VoiceDictationService? voice,
  ReceiptMappingStore? mappingStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (photoSource != null)
          receiptPhotoSourceProvider.overrideWithValue(photoSource),
        if (fileSource != null)
          receiptFileSourceProvider.overrideWithValue(fileSource),
        if (recognizer != null)
          ocrTextRecognizerProvider.overrideWithValue(recognizer),
        if (voice != null)
          voiceDictationServiceProvider.overrideWithValue(voice),
        receiptMappingStoreProvider
            .overrideWithValue(mappingStore ?? _FakeMappingStore()),
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
          'CANTIDAD  DESCRIPCION  PRECIO  IMPORTE',
          '6  COCA COLA 600ML  18.50  111.00',
          r'2 PZ  PAN BIMBO GDE  $52.00  $104.00',
          'TOTAL  215.00',
        ]),
      );
      await tester.tap(find.byKey(const Key('scanReceiptButton')));
      await tester.pumpAndSettle();

      // Pantalla de mapeo con la sugerencia ya aplicada: un toque.
      expect(find.text('Revisar columnas'), findsOneWidget);
      expect(find.text('Ver 2 productos'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ocrMappingConfirm')));
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
    testWidgets('el mapeo confirmado se recuerda para el mismo proveedor',
        (tester) async {
      _setPhoneViewport(tester);
      final store = _FakeMappingStore();
      await _pumpReady(
        tester,
        photoSource: _FakePhotoSource(path: 'factura.jpg'),
        recognizer: _FakeRecognizer([
          'DISTRIBUIDORA BIMBO NORTE',
          'CANTIDAD  DESCRIPCION  PRECIO  IMPORTE',
          '6  COCA COLA 600ML  18.50  111.00',
          'TOTAL  111.00',
        ]),
        mappingStore: store,
      );

      // Primer escaneo: sin recuerdo, avisa que lo guardará.
      await tester.tap(find.byKey(const Key('scanReceiptButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ocrMappingRememberedNotice')), findsNothing);
      expect(
        find.text('Al confirmar se recordará para DISTRIBUIDORA BIMBO NORTE.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('ocrMappingConfirm')));
      await tester.pumpAndSettle();
      expect(store.saved, hasLength(1));
      await tester.tap(find.text('Agregar 1 producto a la orden'));
      await tester.pumpAndSettle();

      // Segundo escaneo del mismo proveedor: abre ya mapeado y lo dice.
      await tester.tap(find.byKey(const Key('scanReceiptButton')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('ocrMappingRememberedNotice')), findsOneWidget);
      expect(find.text('Ver 1 producto'), findsOneWidget);
    });

    testWidgets('cancelar la cámara deja la orden intacta', (tester) async {
      _setPhoneViewport(tester);
      final source = _FakePhotoSource(); // El usuario cierra la cámara.
      await _pumpReady(tester, photoSource: source);
      await tester.tap(find.byKey(const Key('scanReceiptButton')));
      await tester.pumpAndSettle();
      expect(source.calls, 1);
      expect(
          find.text('Aún no agregas productos a esta orden.'), findsOneWidget);
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

  group('ruido no-producto y archivo (Tarea 12.2 — QA de ruido, Q-03)', () {
    testWidgets('los datos del proveedor se dejan fuera y se anuncian',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(
        tester,
        photoSource: _FakePhotoSource(path: 'factura.jpg'),
        recognizer: _FakeRecognizer([
          'DISTRIBUIDORA BIMBO NORTE',
          'RFC: DBN010101XY9',
          'Tel.  55 1234 5678',
          'Fecha  12/09/2026',
          'CANTIDAD  DESCRIPCION  PRECIO  IMPORTE',
          '6  COCA COLA 600ML  18.50  111.00',
          r'2 PZ  PAN BIMBO GDE  $52.00  $104.00',
          'TOTAL  215.00',
        ]),
      );
      await tester.tap(find.byKey(const Key('scanReceiptButton')));
      await tester.pumpAndSettle();

      // El mapeo solo ve la tabla: 2 productos, y dice qué dejó fuera.
      expect(find.text('Ver 2 productos'), findsOneWidget);
      expect(find.text('Se dejaron fuera 3 renglones que no son productos'),
          findsOneWidget);
      expect(find.text('Tel. 55 1234 5678'), findsOneWidget);
      expect(find.text('Fecha 12/09/2026'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ocrMappingConfirm')));
      await tester.pumpAndSettle();

      // El proveedor y el total siguen saliendo de la hoja completa.
      expect(find.textContaining('DISTRIBUIDORA BIMBO NORTE'), findsOneWidget);
      expect(
          find.textContaining('Cuadra con el total impreso'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Tel.'), findsNothing);
      expect(find.byKey(const Key('ocrReviewNoiseHint')), findsOneWidget);
    });

    testWidgets('un PDF de dos páginas entra como una sola factura',
        (tester) async {
      _setPhoneViewport(tester);
      final fileSource = _FakeFileSource(
        capture: const ReceiptCapture(imagePaths: ['p1.jpg', 'p2.jpg']),
      );
      await _pumpReady(
        tester,
        fileSource: fileSource,
        recognizer: _FakePagedRecognizer({
          'p1.jpg': [
            'DISTRIBUIDORA BIMBO NORTE',
            'CANTIDAD  DESCRIPCION  PRECIO  IMPORTE',
            '6  COCA COLA 600ML  18.50  111.00',
          ],
          'p2.jpg': [
            r'2 PZ  PAN BIMBO GDE  $52.00  $104.00',
            'TOTAL  215.00',
          ],
        }),
      );
      await tester.tap(find.byKey(const Key('uploadReceiptButton')));
      await tester.pumpAndSettle();

      expect(fileSource.calls, 1);
      // Una sola pantalla de mapeo con los productos de ambas páginas.
      expect(find.text('Revisar columnas'), findsOneWidget);
      expect(find.text('Ver 2 productos'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ocrMappingConfirm')));
      await tester.pumpAndSettle();

      expect(find.text('2 productos detectados'), findsOneWidget);
      expect(
          find.textContaining('Cuadra con el total impreso'), findsOneWidget);
      await tester.tap(find.text('Agregar 2 productos a la orden'));
      await tester.pumpAndSettle();

      expect(find.text('COCA COLA 600ML'), findsOneWidget);
      expect(find.text('PAN BIMBO GDE'), findsOneWidget);
    });

    testWidgets('cancelar el selector de archivo deja la orden intacta',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(tester, fileSource: _FakeFileSource());

      await tester.tap(find.byKey(const Key('uploadReceiptButton')));
      await tester.pumpAndSettle();

      expect(find.text('Nueva orden de compra'), findsOneWidget);
      expect(find.text('Revisar columnas'), findsNothing);
    });

    testWidgets('un archivo que no se puede abrir lo dice sin romper nada',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(tester, fileSource: _ThrowingFileSource());

      await tester.tap(find.byKey(const Key('uploadReceiptButton')));
      await tester.pumpAndSettle();

      expect(
          find.textContaining('No se pudo abrir el archivo'), findsOneWidget);
      expect(find.text('Nueva orden de compra'), findsOneWidget);
    });
  });

  group('dictado de voz (12.2.3 — un segmento por toque)', () {
    testWidgets(
        'un solo producto dictado se revisa y se agrega a la orden tras enviar',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(
        tester,
        voice: _FakeVoiceService(
          transcript: '36 piezas de Maruchan Pollo a 16 pesos',
        ),
      );
      await _openAndStartDictation(tester);

      // El segmento cerró solo (silencio) y el modal quedó en detenido con
      // el texto listo para revisarse — punto de validación 1.
      expect(
        _transcriptFieldText(tester),
        '36 piezas de Maruchan Pollo a 16 pesos',
      );
      await _submitDictation(tester);

      expect(find.text('Maruchan Pollo'), findsOneWidget);
      expect(find.textContaining('36'), findsWidgets);
    });

    testWidgets(
        'varios productos dictados de corrido se segmentan y agregan todos',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(
        tester,
        voice: _FakeVoiceService(
          transcript: '5 unidades de Coca Cola a 20 pesos también 3 piezas '
              'de jabón Zote a 12 pesos',
        ),
      );
      await _openAndStartDictation(tester);
      await _submitDictation(tester);

      expect(find.text('Coca Cola'), findsOneWidget);
      expect(find.text('jabón Zote'), findsOneWidget);
      expect(find.text('2 productos agregados por dictado'), findsOneWidget);
    });

    testWidgets(
        'al cerrar el segmento el modal queda en detenido — no vuelve a '
        'llamar al motor solo', (tester) async {
      _setPhoneViewport(tester);
      final voice = _FakeVoiceService(
        transcript: '5 unidades de Coca Cola a 20 pesos',
      );
      await _pumpReady(tester, voice: voice);
      await _openAndStartDictation(tester);

      expect(voice.listenCalls, 1);
      expect(find.byKey(const Key('dictationModalStopButton')), findsNothing);
      expect(
          find.byKey(const Key('dictationModalResumeButton')), findsOneWidget);
      expect(find.text('Volver a grabar'), findsOneWidget);
    });

    testWidgets(
        'un error de plataforma deja el modal en detenido y "Volver a '
        'grabar" recupera', (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(
        tester,
        voice: _FakeVoiceService(
          transcript: '5 unidades de Coca Cola a 20 pesos',
          errorOnFirstCall: true,
        ),
      );
      await _openAndStartDictation(tester);

      // El error no dejó el modal muerto en "Escuchando…": está en detenido
      // y el usuario puede volver a intentar.
      expect(find.byKey(const Key('dictationModalStopButton')), findsNothing);
      expect(
          find.byKey(const Key('dictationModalResumeButton')), findsOneWidget);

      await _resumeDictation(tester);
      expect(
          _transcriptFieldText(tester), '5 unidades de Coca Cola a 20 pesos');

      await _submitDictation(tester);
      expect(find.text('Coca Cola'), findsOneWidget);
    });

    testWidgets(
        'un final vacío tras un parcial con contenido no borra lo dictado',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(
        tester,
        voice: _FakeVoiceService(
          transcript: '5 unidades de Coca Cola a 20 pesos',
          prematureEmptyFinal: true,
        ),
      );
      await _openAndStartDictation(tester);

      expect(
          _transcriptFieldText(tester), '5 unidades de Coca Cola a 20 pesos');
      await _submitDictation(tester);
      expect(find.text('Coca Cola'), findsOneWidget);
    });

    testWidgets(
        'una revisión del motor a mitad de segmento no sobreescribe lo ya '
        'dictado', (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(
        tester,
        voice: _FakeVoiceService(
          transcript: '5 unidades de Coca Cola a 20 pesos',
          midSessionRegression: true,
        ),
      );
      await _openAndStartDictation(tester);

      expect(
          _transcriptFieldText(tester), '5 unidades de Coca Cola a 20 pesos');
      await _submitDictation(tester);
      expect(find.text('Coca Cola'), findsOneWidget);
    });

    testWidgets(
        '"Volver a grabar" anexa el segmento nuevo como continuación del '
        'mismo texto', (tester) async {
      _setPhoneViewport(tester);
      final voice = _FakeVoiceService(
        transcript: '5 unidades de Coca Cola a 20 pesos',
      );
      await _pumpReady(tester, voice: voice);
      await _openAndStartDictation(tester);

      voice.queue('también 3 piezas de jabón Zote a 12 pesos');
      await _resumeDictation(tester);

      expect(
        _transcriptFieldText(tester),
        '5 unidades de Coca Cola a 20 pesos también 3 piezas de jabón Zote '
        'a 12 pesos',
      );
      await _submitDictation(tester);
      expect(find.text('2 productos agregados por dictado'), findsOneWidget);
    });

    testWidgets(
        'una corrección a mano entre segmentos se respeta al anexar el '
        'siguiente', (tester) async {
      _setPhoneViewport(tester);
      final voice = _FakeVoiceService(
        transcript: '5 unidades de Coca Cola a 20 pesos',
      );
      await _pumpReady(tester, voice: voice);
      await _openAndStartDictation(tester);

      await tester.enterText(
        find.byKey(const Key('dictationModalTranscriptField')),
        '5 unidades de Coca Cola a 25 pesos',
      );
      await tester.pump();

      voice.queue('también 3 piezas de jabón Zote a 12 pesos');
      await _resumeDictation(tester);

      expect(
        _transcriptFieldText(tester),
        '5 unidades de Coca Cola a 25 pesos también 3 piezas de jabón Zote '
        'a 12 pesos',
      );
    });

    testWidgets(
        'con el micrófono abierto: "Un momento…" hasta que capta, luego '
        '"Escuchando…", y "Detener" cierra con lo captado', (tester) async {
      _setPhoneViewport(tester);
      final voice = _FakeVoiceService(
        transcript: '5 unidades de Coca Cola a 20 pesos',
      );
      await _pumpReady(tester, voice: voice);
      await _openAndStartDictation(tester);
      // Segunda sesión sin nada encolado: queda abierta.
      await _resumeDictation(tester);

      expect(find.text('Un momento…'), findsOneWidget);
      expect(find.text('Escuchando…'), findsNothing);

      voice.micReady();
      await tester.pump();
      expect(find.text('Escuchando…'), findsOneWidget);
      expect(find.text('Un momento…'), findsNothing);

      voice.speak('también 3 piezas de jabón Zote a 12 pesos');
      await tester.pump();
      expect(find.byKey(const Key('dictationModalStopButton')), findsNothing);
      expect(
        _transcriptFieldText(tester),
        '5 unidades de Coca Cola a 20 pesos también 3 piezas de jabón Zote '
        'a 12 pesos',
      );

      // Detener a mano sobre una sesión abierta también cierra.
      await _resumeDictation(tester);
      expect(find.byKey(const Key('dictationModalStopButton')), findsOneWidget);
      await _stopDictation(tester);
      expect(
          find.byKey(const Key('dictationModalResumeButton')), findsOneWidget);
    });

    testWidgets('sin micrófono disponible avisa cómo resolverlo',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(tester, voice: _FakeVoiceService(available: false));
      await tester.tap(find.byKey(const Key('dictationModalOpenButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dictationModalStartButton')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('El dictado no está disponible'),
        findsOneWidget,
      );
    });

    testWidgets(
        'un dictado que no se entiende avisa y no agrega nada a la orden',
        (tester) async {
      _setPhoneViewport(tester);
      await _pumpReady(tester, voice: _FakeVoiceService(transcript: ''));
      await _openAndStartDictation(tester);
      await _submitDictation(tester);

      expect(find.text('No reconocí ningún producto ahí'), findsOneWidget);
      // Modal sigue abierto (no se cierra con un resultado vacío) y la
      // orden sigue sin productos — nunca se inventa un valor.
      expect(
          find.text('Aún no agregas productos a esta orden.'), findsOneWidget);
    });
  });
}
