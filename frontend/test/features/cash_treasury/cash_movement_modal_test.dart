import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/cash_treasury/presentation/cash_session_screen.dart';

Widget _buildApp() {
  return ProviderScope(
    overrides: [
      currentUserNameProvider.overrideWith((ref) => 'Ana García'),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const CashSessionScreen(),
    ),
  );
}

/// Mismo viewport de teléfono que `close_session_wizard_test.dart` — el
/// tamaño 800×600 por defecto de `flutter_test` es demasiado angosto para el
/// modal (formulario + botón CTA).
void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openModal(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Registrar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin movimientos muestra el estado vacío', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Movimientos de caja menor'), findsOneWidget);
    expect(find.text('Sin movimientos registrados en este turno.'), findsOneWidget);
  });

  testWidgets('"Registrar" abre el modal con Retiro/Entrada y botón deshabilitado',
      (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await _openModal(tester);

    expect(find.text('Registrar movimiento'), findsOneWidget);
    expect(find.text('Retiro'), findsOneWidget);
    expect(find.text('Entrada'), findsOneWidget);

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Registrar retiro'),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('registrar un retiro válido lo agrega a la lista y descuenta el efectivo esperado',
      (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    // Fondo inicial mock: $500.00 — efectivo esperado inicial.
    expect(find.textContaining('500.00'), findsWidgets);

    await _openModal(tester);

    await tester.enterText(find.byKey(const Key('cashMovementAmountField')), '50');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ej: Pago de hielo al proveedor'),
      'Compra de hielo',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Registrar retiro'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Movimiento registrado'), findsOneWidget); // SnackBar
    expect(find.text('Compra de hielo'), findsOneWidget);
    // Efectivo esperado: 500 - 50 = 450.00
    expect(find.textContaining('450.00'), findsWidgets);
  });

  testWidgets('un retiro que excede el efectivo disponible muestra error y no se registra',
      (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await _openModal(tester);

    await tester.enterText(find.byKey(const Key('cashMovementAmountField')), '999');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ej: Pago de hielo al proveedor'),
      'Retiro excesivo',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Registrar retiro'));
    await tester.pumpAndSettle();

    expect(find.textContaining('excede el efectivo disponible'), findsOneWidget);
    // El modal sigue abierto — no se registró el movimiento.
    expect(find.text('Registrar movimiento'), findsOneWidget);
  });

  testWidgets('registrar una entrada suma al efectivo esperado', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await _openModal(tester);
    await tester.tap(find.text('Entrada'));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('cashMovementAmountField')), '100');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ej: Pago de hielo al proveedor'),
      'Entrada de cambio',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Registrar entrada'));
    await tester.pumpAndSettle();

    expect(find.text('Entrada de cambio'), findsOneWidget);
    // Efectivo esperado: 500 + 100 = 600.00
    expect(find.textContaining('600.00'), findsWidgets);
  });
}
