import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/purchases/data/purchases_repository.dart';
import 'package:nexus_app/features/purchases/presentation/purchases_provider.dart';
import 'package:nexus_app/features/purchases/presentation/tabs/accounts_payable_tab.dart';

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _buildApp() {
  return ProviderScope(
    // `purchasesRepositoryProvider` ya apunta al backend real (retome de
    // Compras) — estos tests siguen ejercitando el mock a propósito.
    overrides: [
      purchasesRepositoryProvider.overrideWithValue(PurchasesRepositoryMock()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: AccountsPayableTab()),
    ),
  );
}

void main() {
  testWidgets('muestra el resumen agregado y las 3 cuentas por pagar de la semilla', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Pendiente total'), findsOneWidget);
    expect(find.textContaining('Vencido'), findsOneWidget);
    expect(find.text('A tiempo'), findsOneWidget); // ap-po-005
    expect(find.text('Vence pronto'), findsOneWidget); // ap-po-003
    expect(find.text('Vencida'), findsOneWidget); // ap-po-004
  });

  testWidgets('registrar un abono total oculta la tarjeta de la lista', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    // Toma el primer botón "Registrar abono" (ap-po-005, ordenada primero por
    // fecha de vencimiento más próxima entre las que no están vencidas... en
    // realidad el repo ordena ascendente por dueDate, así que la primera es
    // la más próxima a vencer).
    final payButtons = find.widgetWithText(ElevatedButton, 'Registrar abono');
    expect(payButtons, findsWidgets);

    await tester.tap(payButtons.first);
    await tester.pumpAndSettle();

    expect(find.text('Confirmar abono'), findsOneWidget);
    // El monto se precarga con el saldo total pendiente — confirmar liquida
    // la cuenta por completo.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar abono'));
    await tester.pumpAndSettle();

    // Una cuenta menos en el tablero tras la liquidación total.
    expect(find.widgetWithText(ElevatedButton, 'Registrar abono'), findsNWidgets(2));
  });
}
