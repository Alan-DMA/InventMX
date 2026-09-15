import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/purchases/domain/receipt_scan.dart';
import 'package:nexus_app/features/purchases/presentation/ocr_review_screen.dart';

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ReceiptParseResult _result({
  List<DetectedReceiptItem>? items,
  double? total,
  String? supplier,
  int rowsRead = 7,
}) =>
    ReceiptParseResult(
      items: items ??
          const [
            DetectedReceiptItem(
              name: 'COCA COLA 600ML',
              quantity: 6,
              unitPriceMxn: 18.50,
              subtotalMxn: 111.00,
              confidence: 0.95,
            ),
            DetectedReceiptItem(
              name: 'PAN BIMBO GDE',
              quantity: 2,
              unitPriceMxn: 52.00,
              subtotalMxn: 104.00,
              confidence: 0.95,
            ),
          ],
      detectedSupplier: supplier,
      detectedTotalMxn: total,
      rowsRead: rowsRead,
    );

Future<void> _pump(WidgetTester tester, ReceiptParseResult result) async {
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark, home: OcrReviewScreen(result: result)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista los productos detectados y nombra al proveedor leído',
      (tester) async {
    _setPhoneViewport(tester);
    await _pump(tester, _result(supplier: 'DISTRIBUIDORA BIMBO NORTE'));

    expect(find.text('2 productos detectados'), findsOneWidget);
    expect(
      find.textContaining('DISTRIBUIDORA BIMBO NORTE'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'COCA COLA 600ML'), findsOneWidget);
  });

  testWidgets('recuerda que el OCR también lee lo que no es producto',
      (tester) async {
    _setPhoneViewport(tester);
    await _pump(tester, _result());

    expect(find.byKey(const Key('ocrReviewNoiseHint')), findsOneWidget);
    expect(find.textContaining('quítalo con el bote de basura'),
        findsOneWidget);
  });

  testWidgets('confirma el cuadre cuando la suma coincide con el total impreso',
      (tester) async {
    _setPhoneViewport(tester);
    await _pump(tester, _result(total: 215.00));

    expect(find.textContaining('Cuadra con el total impreso'), findsOneWidget);
  });

  testWidgets('señala la diferencia cuando no cuadra contra la factura',
      (tester) async {
    _setPhoneViewport(tester);
    await _pump(tester, _result(total: 300.00));

    expect(find.textContaining('Faltan \$85.00'), findsOneWidget);
  });

  testWidgets('avisa cuando la factura no traía total legible', (tester) async {
    _setPhoneViewport(tester);
    await _pump(tester, _result());

    expect(
      find.textContaining('No se leyó el total impreso'),
      findsOneWidget,
    );
  });

  testWidgets('corregir la cantidad recalcula el total y el cuadre',
      (tester) async {
    _setPhoneViewport(tester);
    await _pump(tester, _result(total: 215.00));

    // La factura decía 6 piezas pero llegaron 5.
    await tester.enterText(find.widgetWithText(TextField, '6'), '5');
    await tester.pumpAndSettle();

    expect(find.text('\$196.50 MXN'), findsOneWidget);
    expect(find.textContaining('Faltan \$18.50'), findsOneWidget);
  });

  testWidgets('quitar un renglón lo descuenta del total', (tester) async {
    _setPhoneViewport(tester);
    await _pump(tester, _result());

    await tester.tap(find.byTooltip('Quitar este renglón').first);
    await tester.pumpAndSettle();

    expect(find.text('1 producto detectado'), findsOneWidget);
    expect(find.text('Agregar 1 producto a la orden'), findsOneWidget);
  });

  testWidgets('un renglón sin costo pide completarlo y no suma al total',
      (tester) async {
    _setPhoneViewport(tester);
    await _pump(
      tester,
      _result(
        items: const [
          DetectedReceiptItem(
            name: 'GALLETAS MARIAS',
            quantity: 4,
            confidence: 0.4,
          ),
        ],
      ),
    );

    expect(find.text('Falta el costo'), findsOneWidget);
    expect(find.text('\$0.00 MXN'), findsOneWidget);

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Agregar 0 productos a la orden'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('un renglón dudoso se marca para revisión', (tester) async {
    _setPhoneViewport(tester);
    await _pump(
      tester,
      _result(
        items: const [
          DetectedReceiptItem(
            name: 'ACEITE 123 1L',
            quantity: 2,
            unitPriceMxn: 45.00,
            subtotalMxn: 90.00,
            confidence: 0.45,
          ),
        ],
      ),
    );

    expect(find.text('Revisar contra la factura'), findsOneWidget);
  });

  testWidgets('aceptar devuelve las líneas ya corregidas', (tester) async {
    _setPhoneViewport(tester);
    OcrReviewOutcome? outcome;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              outcome = await Navigator.of(context).push<OcrReviewOutcome>(
                MaterialPageRoute(
                  builder: (_) => OcrReviewScreen(result: _result()),
                ),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agregar 2 productos a la orden'));
    await tester.pumpAndSettle();

    expect(outcome, isNotNull);
    expect(outcome!.rescanRequested, isFalse);
    expect(outcome!.items, hasLength(2));
    expect(outcome!.items.first.productName, 'COCA COLA 600ML');
    expect(outcome!.items.first.quantity, 6);
    expect(outcome!.items.first.unitCostMxn, 18.50);
  });

  group('sin productos reconocidos', () {
    testWidgets('explica qué pasó y ofrece dos salidas', (tester) async {
      _setPhoneViewport(tester);
      await _pump(tester, _result(items: const [], rowsRead: 9));

      expect(find.text('No se reconocieron productos'), findsOneWidget);
      expect(find.textContaining('Se leyeron 9 renglones'), findsOneWidget);
      expect(find.text('Tomar otra foto'), findsOneWidget);
      expect(find.text('Capturar a mano'), findsOneWidget);
    });

    testWidgets('distingue la foto sin texto legible', (tester) async {
      _setPhoneViewport(tester);
      await _pump(tester, _result(items: const [], rowsRead: 0));

      expect(
        find.textContaining('La foto no tenía texto legible'),
        findsOneWidget,
      );
    });

    testWidgets('"Tomar otra foto" pide un nuevo escaneo', (tester) async {
      _setPhoneViewport(tester);
      OcrReviewOutcome? outcome;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                outcome = await Navigator.of(context).push<OcrReviewOutcome>(
                  MaterialPageRoute(
                    builder: (_) =>
                        OcrReviewScreen(result: _result(items: const [])),
                  ),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tomar otra foto'));
      await tester.pumpAndSettle();

      expect(outcome?.rescanRequested, isTrue);
      expect(outcome?.items, isEmpty);
    });
  });
}
