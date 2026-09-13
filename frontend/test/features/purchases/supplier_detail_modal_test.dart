import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/purchases/domain/supplier.dart';
import 'package:nexus_app/features/purchases/presentation/supplier_detail_modal.dart';

final _supplier = Supplier(
  id: 'sup-001',
  name: 'Distribuidora Bimbo Norte',
  phone: '+525512345678',
  balanceDueMxn: 0,
  createdAt: DateTime(2026, 1, 1),
);

Widget _buildApp() {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showSupplierDetailModal(context, _supplier),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('muestra una "X" explícita para cerrar', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Distribuidora Bimbo Norte'), findsOneWidget);
    expect(find.byTooltip('Cerrar'), findsOneWidget);
  });

  testWidgets('tocar la "X" cierra el modal', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    expect(find.text('Distribuidora Bimbo Norte'), findsNothing);
  });

  testWidgets('el botón atrás del sistema cierra el modal', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Distribuidora Bimbo Norte'), findsOneWidget);

    // Simula el botón/gesto de "atrás" del sistema (Android) — el modal
    // debe reaccionar igual que cualquier otro `showModalBottomSheet` de la
    // app (ajuste de QA: antes no era reactivo por el
    // `DraggableScrollableSheet` que se retiró).
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Distribuidora Bimbo Norte'), findsNothing);
  });
}
