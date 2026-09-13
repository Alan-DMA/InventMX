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
  String? justAddedId,
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: PurchaseItemsSummaryTable(
        items: items,
        onRemove: onRemove ?? (_) {},
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
}
