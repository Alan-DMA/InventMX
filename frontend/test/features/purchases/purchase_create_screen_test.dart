import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/purchases/presentation/purchase_create_screen.dart';

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Monta `PurchaseCreateScreen` y avanza el reloj falso más allá del
/// `_fakeDelay` (500 ms) del mock ANTES de cualquier `pumpAndSettle()` — la
/// pantalla no muestra un spinner indeterminado mientras carga proveedores,
/// así que `pumpAndSettle()` podría "asentarse" antes de que el Timer del
/// mock llegue a disparar, dejándolo pendiente al terminar el test.
Future<void> _pumpReady(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child:
          MaterialApp(theme: AppTheme.dark, home: const PurchaseCreateScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('el botón de crear está deshabilitado sin proveedor ni productos',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Crear orden de compra'),
    );
    expect(btn.onPressed, isNull);
    expect(find.text('Aún no agregas productos a esta orden.'), findsOneWidget);
  });

  testWidgets(
      '"Agregar" con datos válidos añade la línea a la tabla de resumen y limpia el formulario',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    await tester.enterText(
        find.byKey(const Key('purchaseEntryNameField')), 'Pan de caja');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryQtyField')), '10');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryCostField')), '25');
    await tester.pump();

    expect(find.text('Subtotal: \$250.00'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pump();

    // La línea aparece en la tabla de resumen...
    expect(find.text('Pan de caja'), findsOneWidget);
    expect(find.text('10 × \$25.00'), findsOneWidget);
    // ...y el formulario de captura queda limpio, listo para otra línea.
    expect(
      tester
          .widget<TextFormField>(
              find.byKey(const Key('purchaseEntryNameField')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('Aún no agregas productos a esta orden.'), findsNothing);
  });

  testWidgets('quitar una línea de la tabla de resumen la elimina del total',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    await tester.enterText(
        find.byKey(const Key('purchaseEntryNameField')), 'Pan de caja');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryQtyField')), '10');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryCostField')), '25');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pump();

    expect(find.text('Pan de caja'), findsOneWidget);

    await tester.tap(find.byTooltip('Quitar'));
    await tester.pump();

    expect(find.text('Pan de caja'), findsNothing);
    expect(find.text('Aún no agregas productos a esta orden.'), findsOneWidget);
  });

  testWidgets('cada nueva línea se agrega arriba de la tabla, no abajo',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    Future<void> addLine(String name, String qty, String cost) async {
      await tester.enterText(
          find.byKey(const Key('purchaseEntryNameField')), name);
      await tester.enterText(
          find.byKey(const Key('purchaseEntryQtyField')), qty);
      await tester.enterText(
          find.byKey(const Key('purchaseEntryCostField')), cost);
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
      await tester.pump();
    }

    await addLine('Producto A', '1', '10');
    await addLine('Producto B', '1', '10');

    // "Producto B" (agregado después) debe quedar arriba de "Producto A".
    final yA = tester.getTopLeft(find.text('Producto A')).dy;
    final yB = tester.getTopLeft(find.text('Producto B')).dy;
    expect(yB, lessThan(yA));
  });

  testWidgets(
      '"Agregar" cierra el teclado para que la fila recién agregada no quede tapada',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    await tester.enterText(
        find.byKey(const Key('purchaseEntryQtyField')), '10');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryCostField')), '25');
    // `enterText` deja el campo enfocado — simula el teclado abierto.
    await tester.enterText(
        find.byKey(const Key('purchaseEntryNameField')), 'Pan de caja');
    await tester.pump();
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((e) => e.focusNode.hasFocus),
      isTrue,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pumpAndSettle();

    // Ningún campo de texto conserva el foco — el teclado se cierra.
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((e) => e.focusNode.hasFocus),
      isFalse,
    );
  });

  testWidgets(
      'tener productos pero ningún proveedor mantiene el botón de crear deshabilitado',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    await tester.enterText(
        find.byKey(const Key('purchaseEntryNameField')), 'Pan de caja');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryQtyField')), '10');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryCostField')), '25');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pump();

    // Selección del proveedor vía el overlay de `DropdownButtonFormField` se
    // deja fuera de este test (interacción del framework, no lógica propia)
    // — `createOrder` ya está cubierto en `purchases_provider_test.dart`.
    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Crear orden de compra'),
    );
    expect(btn.onPressed, isNull);
  });
}
