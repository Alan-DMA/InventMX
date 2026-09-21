import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/purchases/data/purchases_repository.dart';
import 'package:nexus_app/features/purchases/domain/supplier.dart';
import 'package:nexus_app/features/purchases/presentation/purchases_provider.dart';
import 'package:nexus_app/features/purchases/presentation/supplier_detail_modal.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/add_supplier_modal.dart';

// ---------------------------------------------------------------------------
// U-07 (C-01) — editar y dar de baja proveedor
// ---------------------------------------------------------------------------

final _existing = Supplier(
  id: 'sup-002',
  name: 'Distribuidora La Central',
  phone: '+525512345678',
  rfc: 'DLC010203AB1',
  status: SupplierStatus.active,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
);

Widget _app(Widget home) => ProviderScope(
      overrides: [purchasesRepositoryProvider.overrideWithValue(PurchasesRepositoryMock())],
      child: MaterialApp(theme: AppTheme.dark, home: home),
    );

void main() {
  group('Repositorio mock', () {
    test('updateSupplier cambia solo lo enviado y conserva el resto', () async {
      final repo = PurchasesRepositoryMock();
      final before = (await repo.listSuppliers()).firstWhere((s) => s.id == 'sup-002');

      final updated = await repo.updateSupplier(id: 'sup-002', name: 'Nuevo nombre');

      expect(updated.name, 'Nuevo nombre');
      expect(updated.phone, before.phone);
      expect(updated.rfc, before.rfc);
      expect(updated.creditDays, before.creditDays);
      final after = (await repo.listSuppliers()).firstWhere((s) => s.id == 'sup-002');
      expect(after.name, 'Nuevo nombre');
    });

    test('deactivateSupplier rechaza con 422 si hay órdenes activas (sent / partial)', () async {
      final repo = PurchasesRepositoryMock();
      // sup-001 tiene una orden SENT; sup-003 una PARTIAL_RECEIVED.
      expect(
        () => repo.deactivateSupplier('sup-001'),
        throwsA(isA<SupplierHasActiveOrdersException>()),
      );
      expect(
        () => repo.deactivateSupplier('sup-003'),
        throwsA(isA<SupplierHasActiveOrdersException>()),
      );
    });

    test('deactivateSupplier quita al proveedor sin órdenes activas', () async {
      final repo = PurchasesRepositoryMock();
      await repo.deactivateSupplier('sup-002'); // solo tiene una orden RECEIVED
      final ids = (await repo.listSuppliers()).map((s) => s.id);
      expect(ids, isNot(contains('sup-002')));
    });

    test('el mensaje del 422 nombra el número de órdenes', () {
      expect(const SupplierHasActiveOrdersException(1).message, contains('1 orden activa'));
      expect(const SupplierHasActiveOrdersException(3).message, contains('3 órdenes activas'));
    });
  });

  testWidgets('AddSupplierModal en modo edición prellena, separa la lada y guarda cambios',
      (tester) async {
    await tester.pumpWidget(_app(Scaffold(body: AddSupplierModal(initial: _existing))));
    await tester.pumpAndSettle();

    expect(find.text('Editar proveedor'), findsOneWidget);
    expect(find.text('Guardar cambios'), findsOneWidget);
    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    expect(fields.any((f) => f.controller?.text == 'Distribuidora La Central'), isTrue);
    // Lada +52 separada del número
    expect(fields.any((f) => f.controller?.text == '5512345678'), isTrue);
    expect(fields.any((f) => f.controller?.text == 'DLC010203AB1'), isTrue);

    // El botón arranca habilitado (datos válidos) — no obliga a reescribir
    final btn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Guardar cambios'));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('el detalle ofrece Editar y Dar de baja; la baja pide confirmación con el nombre',
      (tester) async {
    await tester.pumpWidget(_app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showSupplierDetailModal(context, _existing),
            child: const Text('abrir'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('editSupplierButton')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('deactivateSupplierButton')));
    await tester.tap(find.byKey(const Key('deactivateSupplierButton')));
    await tester.pumpAndSettle();

    expect(find.text('¿Dar de baja a Coca-Cola FEMSA Regional?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDeactivateSupplier')));
    await tester.pump(const Duration(seconds: 1)); // delay del mock
    await tester.pumpAndSettle();

    // La hoja se cerró y el aviso confirma la baja
    expect(find.byKey(const Key('editSupplierButton')), findsNothing);
    expect(find.text('Coca-Cola FEMSA Regional dado de baja.'), findsOneWidget);
  });

  testWidgets('con órdenes activas la baja se rechaza y explica por qué', (tester) async {
    final withOrders = Supplier(
      id: 'sup-001',
      name: 'Abarrotes del Norte',
      phone: '+525500000000',
      status: SupplierStatus.active,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    await tester.pumpWidget(_app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showSupplierDetailModal(context, withOrders),
            child: const Text('abrir'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('deactivateSupplierButton')));
    await tester.tap(find.byKey(const Key('deactivateSupplierButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeactivateSupplier')));
    await tester.pump(const Duration(seconds: 1)); // delay del mock
    await tester.pumpAndSettle();

    expect(find.textContaining('orden activa'), findsOneWidget);
    // La hoja sigue abierta: el proveedor no se fue
    expect(find.byKey(const Key('editSupplierButton')), findsOneWidget);
  });
}
