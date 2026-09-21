import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/purchases/data/purchases_repository.dart';
import 'package:nexus_app/features/purchases/presentation/purchases_provider.dart';
import 'package:nexus_app/features/purchases/presentation/tabs/purchase_orders_tab.dart';

/// Viewport de teléfono — mismo criterio que `close_session_wizard_test.dart`:
/// el tamaño 800×600 por defecto de `flutter_test` corta la barra de
/// búsqueda + la fila de chips + filtro.
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
      home: const Scaffold(body: PurchaseOrdersTab()),
    ),
  );
}

void main() {
  testWidgets('muestra las 3 tarjetas visibles del chip "Todas" con sus badges', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Todas'), findsOneWidget);
    expect(find.text('5'), findsOneWidget); // badge del chip "Todas"
    expect(find.text('OC-2026-000012'), findsOneWidget);
    expect(find.text('Distribuidora Bimbo Norte'), findsWidgets);
  });

  testWidgets('el chip "Recibidas" filtra la lista a órdenes RECEIVED', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    // La barra de chips vive en un `SingleChildScrollView` horizontal — con
    // la fuente de prueba (más ancha que la real) puede quedar fuera del
    // viewport visible, igual que en `cash_session_summary_screen_test.dart`.
    await tester.ensureVisible(find.text('Recibidas'));
    await tester.tap(find.text('Recibidas'));
    await tester.pumpAndSettle();

    expect(find.text('OC-2026-000012'), findsNothing); // SENT — no es "Recibidas"
    expect(find.text('OC-2026-000013'), findsOneWidget); // RECEIVED
    expect(find.text('En almacén'), findsWidgets);
  });

  testWidgets('la barra de búsqueda fija filtra por folio', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    // Ajuste de QA: en Compras la búsqueda es una barra fija sobre los
    // chips (no un ícono expandible) — visible desde el primer frame.
    await tester.enterText(find.byType(TextField), '000014');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.text('OC-2026-000014'), findsOneWidget);
    expect(find.text('OC-2026-000012'), findsNothing);
  });
}
