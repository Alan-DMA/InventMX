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

/// El tamaño de pantalla por defecto de flutter_test es 800×600 (más ancho
/// que alto) — nada parecido a un teléfono real y demasiado bajo para el
/// wizard (stepper + tarjeta de turno + barra inferior fija ya consumen
/// buena parte de esos 600px). Se fuerza un viewport de teléfono realista.
void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('abre una sesión automáticamente y muestra el turno activo',
      (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.text('TURNO ABIERTO'), findsOneWidget);
    expect(find.text('Ana García'), findsOneWidget);
    expect(find.textContaining('Fondo inicial'), findsOneWidget);
    expect(find.textContaining('Efectivo esperado'), findsOneWidget);
  });

  testWidgets('Cerrar turno abre el wizard en el Paso 1 con el turno visible',
      (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Cerrar turno'));
    await tester.pumpAndSettle();

    expect(find.text('Arqueo de Caja'), findsOneWidget);
    expect(find.text('Ingreso de Denominaciones'), findsOneWidget);
    expect(find.text('Ana García'), findsOneWidget); // ShiftInfoCard
  });

  testWidgets(
      'agregar efectivo y avanzar muestra el Paso 2 con el total físico',
      (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Cerrar turno'));
    await tester.pumpAndSettle();

    // Agrega 2 billetes de $1000 (denominación por defecto).
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pump();

    expect(find.text('\$2000.00'), findsWidgets); // total contado en la barra inferior

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'));
    await tester.pumpAndSettle();

    expect(find.text('Resumen y Confirmación'), findsOneWidget);
    expect(find.text('Efectivo físico contado'), findsOneWidget);
    // Sin ventas mock previas, lo esperado es solo el fondo inicial ($500),
    // por lo que $2000 contados dan un sobrante.
    expect(find.text('Sobrante'), findsOneWidget);
  });

  testWidgets(
      'enfocar el campo Cant. oculta la barra inferior y "Agregar" desenfoca y la restaura',
      (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Cerrar turno'));
    await tester.pumpAndSettle();

    expect(find.text('Siguiente'), findsOneWidget);
    expect(find.text('TOTAL CONTADO'), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pump();

    // Mientras "Cant." tiene foco, la barra inferior se oculta por completo
    // — "Agregar" queda como único botón visible, evitando el overflow que
    // provocaba el Scaffold padre al reducir la altura disponible.
    expect(find.text('Siguiente'), findsNothing);
    expect(find.text('TOTAL CONTADO'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Agregar'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pump();

    // _add() desenfoca el campo — la barra inferior vuelve a aparecer.
    expect(find.text('Siguiente'), findsOneWidget);
    expect(find.text('TOTAL CONTADO'), findsOneWidget);
  });

  testWidgets('confirmar el cierre regresa a Caja con un turno nuevo abierto',
      (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Cerrar turno'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar Cierre'));
    await tester.pumpAndSettle();

    // Vuelve a la pantalla de Caja con un turno nuevo (mock) ya abierto.
    expect(find.text('Arqueo de Caja'), findsNothing);
    expect(find.text('TURNO ABIERTO'), findsOneWidget);
    expect(find.textContaining('Turno cerrado'), findsOneWidget); // SnackBar
  });
}
