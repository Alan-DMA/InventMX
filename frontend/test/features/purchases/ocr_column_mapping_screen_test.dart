import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/core/utils/ocr_helper.dart';
import 'package:nexus_app/features/purchases/domain/receipt_scan.dart';
import 'package:nexus_app/features/purchases/presentation/ocr_column_mapping_screen.dart';

/// Orden de compra con la que Eduardo probó el OCR (índice, descripción,
/// unidades, precio unitario, % dto, precio dto, total).
const _purchaseOrder = OcrTable(cells: [
  [
    'Artículo',
    'Descripción',
    'Unidades',
    'Precio unitario',
    '% Dto.',
    'Precio Dto.',
    'Total'
  ],
  ['1', 'ARTICULO 1', '20', '5', '0', '0,00', '100,00'],
  ['2', 'ARTICULO 2', '15', '1', '0', '0', '15'],
  ['3', 'ARTICULO 3', '30', '5', '0', '0', '150'],
  ['4', 'ARTICULO 4', '20', '2', '0', '0', '40'],
  ['5', 'ARTICULO 5', '3', '10', '0', '0', '30'],
  ['6', 'ARTICULO 6', '10', '10', '0', '0', '100'],
  ['7', 'ARTICULO 7', '10', '5', '0', '0', '50'],
]);

const _suggested = ReceiptColumnMapping(
  nameCol: 1,
  quantityCol: 2,
  priceCol: 3,
  subtotalCol: 6,
);

/// Lo que devolvió la pantalla al cerrarse — se llena cuando hace `pop`.
class _Harness {
  OcrColumnMappingOutcome? outcome;
  bool closed = false;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  OcrTable table = _purchaseOrder,
  ReceiptColumnMapping? suggested = _suggested,
  ReceiptColumnMapping? remembered,
  String? supplier,
}) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final harness = _Harness();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                harness.outcome =
                    await Navigator.of(context).push<OcrColumnMappingOutcome>(
                  MaterialPageRoute(
                    builder: (_) => OcrColumnMappingScreen(
                      table: table,
                      suggested: suggested,
                      remembered: remembered,
                      supplier: supplier,
                    ),
                  ),
                );
                harness.closed = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return harness;
}

/// Elige en el selector [fieldKey] la columna cuya muestra es [sample].
Future<void> _select(WidgetTester tester, Key fieldKey, String sample) async {
  final dropdown = find.descendant(
    of: find.byKey(fieldKey),
    matching: find.byType(DropdownButton<String>),
  );
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(sample).last);
  await tester.pumpAndSettle();
}

void main() {
  group('OcrColumnMappingScreen', () {
    testWidgets('abre con la sugerencia aplicada y un solo toque confirma',
        (tester) async {
      await _pump(tester);

      expect(find.text('Revisar columnas'), findsOneWidget);
      expect(find.text('Ver 7 productos'), findsOneWidget);
      // Los chips marcan las columnas asignadas sobre el grid.
      expect(find.text('Nombre'), findsWidgets);
      expect(find.text('Cantidad'), findsWidgets);
      expect(find.text('Precio'), findsWidgets);
    });

    testWidgets('confirmar devuelve los productos y el mapeo', (tester) async {
      final harness = await _pump(tester);

      await tester.tap(find.byKey(const Key('ocrMappingConfirm')));
      await tester.pumpAndSettle();

      expect(harness.closed, isTrue);
      final outcome = harness.outcome!;
      expect(outcome.rescanRequested, isFalse);
      expect(outcome.mapping, _suggested);
      expect(outcome.items, hasLength(7));
      expect(outcome.items.first.name, 'ARTICULO 1');
      expect(outcome.items.first.quantity, 20);
      expect(outcome.items.first.unitPriceMxn, 5);
    });

    testWidgets('sin sugerencia el CTA explica qué falta y no deja avanzar',
        (tester) async {
      await _pump(tester, suggested: null);

      expect(find.text('Falta elegir Nombre'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('ocrMappingConfirm')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('elegir la columna que faltaba habilita el CTA con el conteo',
        (tester) async {
      await _pump(
        tester,
        suggested: const ReceiptColumnMapping(nameCol: 1, quantityCol: 2),
      );
      expect(find.text('Falta elegir Precio'), findsOneWidget);

      await _select(
          tester, const Key('ocrMappingPrice'), 'Precio unitario, 5, 1');

      expect(find.text('Ver 7 productos'), findsOneWidget);
      expect(find.text('Falta elegir Precio'), findsNothing);
    });

    testWidgets('con proveedor recordado abre con su mapeo y lo dice',
        (tester) async {
      const remembered = ReceiptColumnMapping(
        nameCol: 1,
        quantityCol: 2,
        priceCol: 6, // distinto de la sugerencia: se nota si gana.
      );
      await _pump(
        tester,
        remembered: remembered,
        supplier: 'DISTRIBUIDORA BIMBO NORTE',
      );

      expect(
          find.byKey(const Key('ocrMappingRememberedNotice')), findsOneWidget);
      expect(
        find.textContaining('Usando el mapeo de DISTRIBUIDORA BIMBO NORTE'),
        findsOneWidget,
      );
      // El selector de precio muestra la muestra de la columna 6 (totales).
      expect(find.text('Total, 100,00, 15'), findsOneWidget);
    });

    testWidgets('un mapeo recordado que no cabe en esta tabla se ignora',
        (tester) async {
      await _pump(
        tester,
        remembered: const ReceiptColumnMapping(
            nameCol: 1, quantityCol: 2, priceCol: 12),
        supplier: 'BIMBO',
      );

      expect(find.byKey(const Key('ocrMappingRememberedNotice')), findsNothing);
      expect(find.text('Ver 7 productos'), findsOneWidget); // la sugerencia
      expect(
          find.text('Al confirmar se recordará para BIMBO.'), findsOneWidget);
    });

    testWidgets('"Tomar otra foto" devuelve la señal de re-escaneo',
        (tester) async {
      final harness = await _pump(tester);

      await tester.tap(find.byKey(const Key('ocrMappingRescan')));
      await tester.pumpAndSettle();

      expect(harness.outcome!.rescanRequested, isTrue);
    });

    testWidgets('el grid recorta la vista previa y avisa cuántas filas faltan',
        (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('ocrMappingGrid')), findsOneWidget);
      expect(find.text('y 2 filas más'), findsOneWidget);
    });

    testWidgets('anuncia los renglones que se dejaron fuera, con muestras',
        (tester) async {
      final withNoise = OcrTable(
        cells: _purchaseOrder.cells,
        ignoredRows: const [
          'Tel. 55 1234 5678',
          'Fecha 12/09/2026',
          'RFC: ALO010101XY9',
          'Folio A-00123',
        ],
      );
      await _pump(tester, table: withNoise);

      expect(find.byKey(const Key('ocrMappingIgnoredNotice')), findsOneWidget);
      expect(find.text('Se dejaron fuera 4 renglones que no son productos'),
          findsOneWidget);
      expect(find.text('Tel. 55 1234 5678'), findsOneWidget);
      expect(find.text('Fecha 12/09/2026'), findsOneWidget);
      expect(find.text('RFC: ALO010101XY9'), findsOneWidget);
      // Solo tres muestras; el resto se cuenta.
      expect(find.text('Folio A-00123'), findsNothing);
      expect(find.text('y 1 más'), findsOneWidget);
      // El CTA sigue contando solo productos.
      expect(find.text('Ver 7 productos'), findsOneWidget);
    });

    testWidgets('en singular cuando se dejó fuera un solo renglón',
        (tester) async {
      final withNoise = OcrTable(
        cells: _purchaseOrder.cells,
        ignoredRows: const ['Fecha 12/09/2026'],
      );
      await _pump(tester, table: withNoise);

      expect(find.text('Se dejó fuera 1 renglón que no es producto'),
          findsOneWidget);
      expect(find.text('y 1 más'), findsNothing);
    });

    testWidgets('sin ruido no muestra el aviso', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('ocrMappingIgnoredNotice')), findsNothing);
    });
  });
}
