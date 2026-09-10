import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';
import 'package:nexus_app/features/sales_pos/presentation/widgets/payment_modal.dart';

/// Tests de widget — Tarea 7.2 (`PaymentModal`).
///
/// Monta el modal directamente como pantalla (mismo patrón que
/// add_product_modal_test.dart) para evitar la complejidad de abrirlo
/// desde un showModalBottomSheet real en cada test.
void main() {
  Widget buildModal({double totalMxn = 42.0}) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: PaymentModal(totalMxn: totalMxn),
      ),
    );
  }

  Future<void> addPayment(
    WidgetTester tester, {
    required String amount,
  }) async {
    await tester.enterText(find.byType(TextField).first, amount);
    await tester.pump();
    final addButton = find.widgetWithText(ElevatedButton, 'Agregar método');
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pump();
  }

  testWidgets('agregar método suma a la lista y actualiza Pagado',
      (tester) async {
    await tester.pumpWidget(buildModal(totalMxn: 40));

    await addPayment(tester, amount: '25.00');

    expect(find.text('PAGOS INGRESADOS (1)'), findsOneWidget);
    expect(find.text('Efectivo'), findsWidgets);
    // Pagado debe reflejar el monto ingresado.
    expect(find.text('\$25.00'), findsWidgets);
  });

  testWidgets('eliminar fila recalcula el resumen', (tester) async {
    await tester.pumpWidget(buildModal(totalMxn: 40));

    await addPayment(tester, amount: '50.00');
    expect(find.text('PAGOS INGRESADOS (1)'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump();

    expect(find.text('PAGOS INGRESADOS (0)'), findsOneWidget);
    expect(find.text('Aún no agregas ningún método'), findsOneWidget);
  });

  testWidgets('pagado menor a total muestra Faltan y deshabilita botón',
      (tester) async {
    await tester.pumpWidget(buildModal(totalMxn: 42));

    await addPayment(tester, amount: '20.00');

    expect(find.text('Faltan'), findsOneWidget);
    expect(find.text('\$22.00 MXN'), findsOneWidget);

    final confirmButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Confirmar cobro \$42.00 MXN'),
    );
    expect(confirmButton.onPressed, isNull);
  });

  testWidgets('pagado mayor o igual a total muestra Cambio a devolver',
      (tester) async {
    await tester.pumpWidget(buildModal(totalMxn: 42));

    await addPayment(tester, amount: '45.00');

    expect(find.text('Cambio a devolver'), findsOneWidget);
    expect(find.text('\$3.00 MXN'), findsOneWidget);

    final confirmButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Confirmar cobro \$42.00 MXN'),
    );
    expect(confirmButton.onPressed, isNotNull);
  });

  testWidgets('folio solo visible si método no es Efectivo', (tester) async {
    await tester.pumpWidget(buildModal());

    expect(find.text('Folio o referencia (opcional)'), findsNothing);

    // Cambia el dropdown a SPEI.
    await tester.tap(find.byType(DropdownButton<PaymentMethodMxn>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SPEI').last);
    await tester.pumpAndSettle();

    expect(find.text('Folio o referencia (opcional)'), findsOneWidget);
  });

  testWidgets('confirmar retorna la lista de pagos y cierra el modal',
      (tester) async {
    List<PaymentEntry>? popped;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                popped = await showPaymentModal(context, totalMxn: 30);
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await addPayment(tester, amount: '30.00');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar cobro \$30.00 MXN'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.length, 1);
    expect(popped!.first.amountMxn, 30.0);
    expect(find.byType(PaymentModal), findsNothing);
  });

  testWidgets(
      'no hace overflow con teclado abierto y mantiene el alto del modal '
      'estable al agregar el primer pago', (tester) async {
    // Viewport realista de un Android común (~360x780 lógicos) + teclado
    // numérico abierto (~260 lógicos, ~33% de la pantalla) — reproduce el
    // escenario reportado en QA: overflow de ~7px al tipear el monto.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildModal(totalMxn: 33));

    // Simula el teclado abriéndose (numérico) al enfocar el campo de monto.
    final amountField = find.byType(TextField).first;
    await tester.tap(amountField);
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 780);
    addTearDown(() => tester.view.resetViewInsets());
    // pumpAndSettle: el foco en el campo dispara Scrollable.ensureVisible,
    // que anima el scroll interno del modal — hay que esperarlo antes de
    // medir tamaños o tocar otros widgets.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Altura del modal antes de agregar el primer pago.
    final sizeBefore = tester.getSize(find.byType(PaymentModal));

    await addPayment(tester, amount: '20.00');
    expect(tester.takeException(), isNull);

    final sizeAfter = tester.getSize(find.byType(PaymentModal));

    // El alto del modal no debe cambiar al agregar el primer pago.
    expect(sizeAfter.height, sizeBefore.height);
  });

  testWidgets(
      'no hace overflow en un Android pequeño con folio visible y teclado '
      'abierto (peor caso combinado)', (tester) async {
    // Gama baja aún soportada por el proyecto: ~360x780 lógicos (resolución
    // real común, p.ej. 1080x2340 @3.0), con un método que muestra el campo
    // de folio (variante más alta del formulario) y el teclado abierto.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildModal(totalMxn: 33));

    // Cambia a SPEI para que se muestre el campo de folio/referencia.
    await tester.tap(find.byType(DropdownButton<PaymentMethodMxn>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SPEI').last);
    await tester.pumpAndSettle();

    final amountField = find.byType(TextField).first;
    await tester.tap(amountField);
    await tester.pump();
    // Teclado numérico moderado (~25% del alto de pantalla).
    tester.view.viewInsets = const FakeViewPadding(bottom: 585);
    addTearDown(() => tester.view.resetViewInsets());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelar no modifica el carrito (retorna null)',
      (tester) async {
    List<PaymentEntry>? popped = [];

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                popped = await showPaymentModal(context, totalMxn: 30);
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(popped, isNull);
  });
}
