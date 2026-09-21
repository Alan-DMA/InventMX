import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/purchases/data/purchases_repository.dart';
import 'package:nexus_app/features/purchases/presentation/purchases_provider.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/add_supplier_modal.dart';

/// Monta el modal directamente (no vía `showAddSupplierModal`) para poder
/// capturar el `ProviderContainer` y verificar el efecto de `_submit` sobre
/// `suppliersProvider`.
Future<ProviderContainer> _pumpModal(WidgetTester tester) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      // `purchasesRepositoryProvider` ya apunta al backend real (retome de
      // Compras) — este test sigue ejercitando el mock a propósito.
      overrides: [
        purchasesRepositoryProvider
            .overrideWithValue(PurchasesRepositoryMock()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Consumer(builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const Scaffold(body: AddSupplierModal());
        }),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('el código de región por defecto es México (+52)', (tester) async {
    await _pumpModal(tester);
    expect(find.text('🇲🇽 +52'), findsOneWidget);
  });

  testWidgets('cambiar el código de región antepone el nuevo código al crear el proveedor',
      (tester) async {
    final container = await _pumpModal(tester);

    await tester.tap(find.text('🇲🇽 +52'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🇺🇸 +1').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Ej: Distribuidora Bimbo Norte'), 'Proveedor Test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Ej: 5512345678'), '4155551234');
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar proveedor'));
    await tester.pumpAndSettle();

    final created = container.read(suppliersProvider).suppliers.first;
    expect(created.name, 'Proveedor Test');
    expect(created.phone, '+14155551234');
  });

  testWidgets('sin cambiar el código, el teléfono se guarda con +52', (tester) async {
    final container = await _pumpModal(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Ej: Distribuidora Bimbo Norte'), 'Otro Proveedor');
    await tester.enterText(find.widgetWithText(TextFormField, 'Ej: 5512345678'), '5512345678');
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar proveedor'));
    await tester.pumpAndSettle();

    final created = container.read(suppliersProvider).suppliers.first;
    expect(created.phone, '+525512345678');
  });

  group('días de crédito (hallazgo de QA, Sep 19)', () {
    testWidgets('el plazo capturado llega al proveedor creado', (tester) async {
      final container = await _pumpModal(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Ej: Distribuidora Bimbo Norte'),
          'Proveedor a crédito');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Ej: 5512345678'), '5512345678');
      await tester.enterText(
          find.byKey(const Key('supplierCreditDaysField')), '30');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar proveedor'));
      await tester.pumpAndSettle();

      expect(container.read(suppliersProvider).suppliers.first.creditDays, 30);
    });

    testWidgets('dejarlo vacío es de contado (0 días), no un valor inventado',
        (tester) async {
      final container = await _pumpModal(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Ej: Distribuidora Bimbo Norte'),
          'Proveedor de contado');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Ej: 5512345678'), '5512345678');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar proveedor'));
      await tester.pumpAndSettle();

      expect(container.read(suppliersProvider).suppliers.first.creditDays, 0);
    });
  });
}
