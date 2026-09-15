import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/purchases/domain/purchase_order.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/purchase_items_summary_table.dart';

List<PurchaseOrderItem> _makeItems(int count) {
  return List.generate(
    count,
    (i) => PurchaseOrderItem(
      productId: 'prod-$i',
      productName: 'Producto $i',
      quantity: i + 1,
      unitCostMxn: 10.0,
    ),
  );
}

Widget _buildTable(
  List<PurchaseOrderItem> items, {
  ValueChanged<PurchaseOrderItem>? onRemove,
  ValueChanged<PurchaseOrderItem>? onEdit,
  String? justAddedId,
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: PurchaseItemsSummaryTable(
        items: items,
        onRemove: onRemove ?? (_) {},
        onEdit: onEdit ?? (_) {},
        justAddedId: justAddedId,
      ),
    ),
  );
}

/// El único `Container` de la fila con `color:` explícito (no `decoration:`)
/// es el destello de "recién agregado" en `_ItemRow` — el resto de
/// contenedores del árbol usan `decoration: BoxDecoration(...)`.
Finder get _flashContainer => find.byWidgetPredicate(
      (w) => w is Container && w.color != null,
    );

void main() {
  testWidgets('sin productos muestra el estado vacío', (tester) async {
    await tester.pumpWidget(_buildTable(const []));
    await tester.pump();

    expect(find.text('Aún no agregas productos a esta orden.'), findsOneWidget);
  });

  testWidgets('con 3 líneas o menos se muestran todas sin scroll interno', (tester) async {
    final items = _makeItems(3);
    await tester.pumpWidget(_buildTable(items));
    await tester.pump();

    expect(find.byType(ListView), findsNothing);
    for (final item in items) {
      expect(find.text(item.productName), findsOneWidget);
    }
  });

  testWidgets('con más de 3 líneas activa scroll interno con altura acotada', (tester) async {
    final items = _makeItems(6);
    await tester.pumpWidget(_buildTable(items));
    await tester.pump();

    expect(find.byType(ListView), findsOneWidget);

    final constrainedBox = tester.widget<ConstrainedBox>(
      find.ancestor(of: find.byType(ListView), matching: find.byType(ConstrainedBox)).first,
    );
    expect(constrainedBox.constraints.maxHeight.isFinite, isTrue);
    expect(constrainedBox.constraints.maxHeight, lessThan(6 * 58.0));

    // La primera línea sigue siendo legible dentro del alto acotado.
    expect(find.text('Producto 0'), findsOneWidget);
  });

  testWidgets('tocar "Quitar" en una línea invoca onRemove con ese ítem', (tester) async {
    final items = _makeItems(2);
    PurchaseOrderItem? removed;
    await tester.pumpWidget(_buildTable(items, onRemove: (i) => removed = i));
    await tester.pump();

    await tester.tap(find.byTooltip('Quitar').first);
    await tester.pump();

    expect(removed, items.first);
  });

  testWidgets('justAddedId destella la fila recién agregada y se desvanece — ajuste de QA',
      (tester) async {
    final items = _makeItems(1);
    await tester.pumpWidget(_buildTable(items, justAddedId: items.first.productId));
    await tester.pump();

    // Al primer frame el destello está en su punto más visible.
    expect(_flashContainer, findsOneWidget);

    // Tras la duración de la animación (900 ms), se desvanece por completo.
    await tester.pump(const Duration(milliseconds: 1000));
    final faded = tester.widget<Container>(_flashContainer);
    expect(faded.color!.a, 0);
  });

  testWidgets('sin justAddedId ninguna fila destella', (tester) async {
    final items = _makeItems(2);
    await tester.pumpWidget(_buildTable(items));
    await tester.pump();

    final containers = tester.widgetList<Container>(_flashContainer);
    for (final c in containers) {
      expect(c.color!.a, 0);
    }
  });

  group('edición inline (iteración post-exploración CRF, Tarea 12.2.3)', () {
    testWidgets('tocar una fila la expande con los 3 campos editables',
        (tester) async {
      final items = _makeItems(1);
      await tester.pumpWidget(_buildTable(items));
      await tester.pump();

      expect(find.byKey(Key('purchaseItemEditName-${items.first.productId}')),
          findsNothing);

      await tester.tap(find.text('Producto 0'));
      await tester.pump();

      expect(find.byKey(Key('purchaseItemEditName-${items.first.productId}')),
          findsOneWidget);
      expect(find.byKey(Key('purchaseItemEditQty-${items.first.productId}')),
          findsOneWidget);
      expect(find.byKey(Key('purchaseItemEditCost-${items.first.productId}')),
          findsOneWidget);
    });

    testWidgets('confirmar la edición invoca onEdit con los valores nuevos',
        (tester) async {
      final items = _makeItems(1);
      PurchaseOrderItem? edited;
      await tester.pumpWidget(
          _buildTable(items, onEdit: (i) => edited = i));
      await tester.pump();

      await tester.tap(find.text('Producto 0'));
      await tester.pump();

      final id = items.first.productId;
      await tester.enterText(
          find.byKey(Key('purchaseItemEditQty-$id')), '9');
      await tester.enterText(
          find.byKey(Key('purchaseItemEditCost-$id')), '15.50');
      await tester.tap(find.byKey(Key('purchaseItemEditConfirm-$id')));
      await tester.pump();

      expect(edited?.quantity, 9);
      expect(edited?.unitCostMxn, 15.50);
      expect(edited?.productName, 'Producto 0');
    });

    testWidgets('cancelar la edición no invoca onEdit y cierra el modo edición',
        (tester) async {
      final items = _makeItems(1);
      var editCalled = false;
      await tester.pumpWidget(
          _buildTable(items, onEdit: (_) => editCalled = true));
      await tester.pump();

      final id = items.first.productId;
      await tester.tap(find.text('Producto 0'));
      await tester.pump();

      await tester.enterText(find.byKey(Key('purchaseItemEditQty-$id')), '99');
      await tester.tap(find.byKey(Key('purchaseItemEditCancel-$id')));
      await tester.pump();

      expect(editCalled, isFalse);
      expect(find.byKey(Key('purchaseItemEditQty-$id')), findsNothing);
    });

    testWidgets('un producto con precio en 0 muestra el chip "falta precio"',
        (tester) async {
      final items = [
        const PurchaseOrderItem(
          productId: 'p1',
          productName: 'Tornillos',
          quantity: 5,
          unitCostMxn: 0,
        ),
      ];
      await tester.pumpWidget(_buildTable(items));
      await tester.pump();

      expect(find.text('falta precio'), findsOneWidget);
      expect(find.text('falta cantidad'), findsNothing);
      expect(find.text('falta nombre'), findsNothing);
    });

    testWidgets('un producto sin nombre ni cantidad muestra ambos chips',
        (tester) async {
      final items = [
        const PurchaseOrderItem(
          productId: 'p1',
          productName: '',
          quantity: 0,
          unitCostMxn: 20,
        ),
      ];
      await tester.pumpWidget(_buildTable(items));
      await tester.pump();

      expect(find.text('falta nombre'), findsOneWidget);
      expect(find.text('falta cantidad'), findsOneWidget);
      expect(find.text('(sin nombre)'), findsOneWidget);
    });

    testWidgets('un producto completo no muestra ningún chip', (tester) async {
      final items = _makeItems(1);
      await tester.pumpWidget(_buildTable(items));
      await tester.pump();

      expect(find.textContaining('falta'), findsNothing);
    });

    testWidgets('"Quitar" en una fila incompleta no dispara el modo edición',
        (tester) async {
      final items = [
        const PurchaseOrderItem(
          productId: 'p1',
          productName: 'Tornillos',
          quantity: 5,
          unitCostMxn: 0,
        ),
      ];
      PurchaseOrderItem? removed;
      await tester.pumpWidget(
          _buildTable(items, onRemove: (i) => removed = i));
      await tester.pump();

      await tester.tap(find.byTooltip('Quitar'));
      await tester.pump();

      expect(removed, items.first);
      expect(find.byKey(const Key('purchaseItemEditName-p1')), findsNothing);
    });
  });
}
