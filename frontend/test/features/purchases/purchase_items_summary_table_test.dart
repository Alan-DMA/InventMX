import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/purchases/domain/purchase_order.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/purchase_items_summary_table.dart';

class _MockInventoryRepository extends Mock implements InventoryRepository {}

Product _product(String id, String name) => Product(
      id: id,
      sku: id.toUpperCase(),
      name: name,
      category: 'General',
      priceMxn: 20,
      costMxn: 10,
      stock: 5,
      reservedStock: 0,
      availableStock: 5,
      isActive: true,
      isOnCatalog: false,
      createdAt: DateTime(2026, 1, 1),
    );

PurchaseOrderItem _item(String id, String name,
        {int quantity = 1, double unitCostMxn = 10}) =>
    PurchaseOrderItem(
      productId: id,
      productName: name,
      quantity: quantity,
      unitCostMxn: unitCostMxn,
    );

/// Renglones ya amarrados al catálogo — el caso normal de la tabla. Los que
/// se van a crear se arman aparte, con `resolved: null`.
List<PurchaseDraftLine> _makeLines(int count) {
  return List.generate(
    count,
    (i) => PurchaseDraftLine(
      item: _item('prod-$i', 'Producto $i', quantity: i + 1),
      resolved: _product('prod-$i', 'Producto $i'),
    ),
  );
}

Widget _buildTable(
  List<PurchaseDraftLine> lines, {
  ValueChanged<String>? onRemove,
  void Function(String, PurchaseOrderItem)? onEdit,
  void Function(String, Product?)? onResolve,
  void Function(String, double)? onSalePriceChanged,
  String? justAddedId,
  List<Product> catalog = const [],
}) {
  final mock = _MockInventoryRepository();
  when(
    () => mock.getProducts(
      query: any(named: 'query'),
      category: any(named: 'category'),
      lowStock: any(named: 'lowStock'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    ),
  ).thenAnswer((_) async => PaginatedProducts(
        items: catalog,
        total: catalog.length,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      ));

  return ProviderScope(
    // La fila en edición monta `ProductField`, que busca en el inventario.
    overrides: [inventoryRepositoryProvider.overrideWithValue(mock)],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: PurchaseItemsSummaryTable(
          lines: lines,
          marginPercent: 40,
          onRemove: onRemove ?? (_) {},
          onEdit: onEdit ?? (_, __) {},
          onResolve: onResolve ?? (_, __) {},
          onSalePriceChanged: onSalePriceChanged ?? (_, __) {},
          justAddedId: justAddedId,
        ),
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

  testWidgets('con 3 líneas o menos se muestran todas sin scroll interno',
      (tester) async {
    final lines = _makeLines(3);
    await tester.pumpWidget(_buildTable(lines));
    await tester.pump();

    expect(find.byType(ListView), findsNothing);
    for (final line in lines) {
      expect(find.text(line.item.productName), findsOneWidget);
    }
  });

  testWidgets('con más de 3 líneas activa scroll interno con altura acotada',
      (tester) async {
    final lines = _makeLines(6);
    await tester.pumpWidget(_buildTable(lines));
    await tester.pump();

    expect(find.byType(ListView), findsOneWidget);

    final constrainedBox = tester.widget<ConstrainedBox>(
      find
          .ancestor(
              of: find.byType(ListView), matching: find.byType(ConstrainedBox))
          .first,
    );
    expect(constrainedBox.constraints.maxHeight.isFinite, isTrue);
    expect(constrainedBox.constraints.maxHeight, lessThan(6 * 78.0));

    // La primera línea sigue siendo legible dentro del alto acotado.
    expect(find.text('Producto 0'), findsOneWidget);
  });

  testWidgets('tocar "Quitar" en una línea invoca onRemove con esa llave',
      (tester) async {
    final lines = _makeLines(2);
    String? removed;
    await tester.pumpWidget(_buildTable(lines, onRemove: (id) => removed = id));
    await tester.pump();

    await tester.tap(find.byTooltip('Quitar').first);
    await tester.pump();

    expect(removed, lines.first.id);
  });

  testWidgets(
      'justAddedId destella la fila recién agregada y se desvanece — ajuste de QA',
      (tester) async {
    final lines = _makeLines(1);
    await tester.pumpWidget(_buildTable(lines, justAddedId: lines.first.id));
    await tester.pump();

    // Al primer frame el destello está en su punto más visible.
    expect(_flashContainer, findsOneWidget);

    // Tras la duración de la animación (900 ms), se desvanece por completo.
    await tester.pump(const Duration(milliseconds: 1000));
    final faded = tester.widget<Container>(_flashContainer);
    expect(faded.color!.a, 0);
  });

  testWidgets('sin justAddedId ninguna fila destella', (tester) async {
    final lines = _makeLines(2);
    await tester.pumpWidget(_buildTable(lines));
    await tester.pump();

    final containers = tester.widgetList<Container>(_flashContainer);
    for (final c in containers) {
      expect(c.color!.a, 0);
    }
  });

  group('productos por crear (retome de Compras)', () {
    testWidgets('un renglón sin resolver se etiqueta y ofrece su precio',
        (tester) async {
      await tester.pumpWidget(_buildTable([
        PurchaseDraftLine(
          item: _item('draft-1', 'Leche Lala 1L', quantity: 12, unitCostMxn: 18.5),
          salePriceMxn: 25.90,
        ),
      ]));
      await tester.pump();

      expect(find.byKey(const Key('purchaseItemWillCreateTag')), findsOneWidget);
      expect(find.text('Se creará'), findsOneWidget);
      expect(find.textContaining('margen 40%'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
                find.byKey(const Key('purchaseItemSalePrice-draft-1')))
            .controller!
            .text,
        '25.90',
      );
    });

    testWidgets('un renglón ya resuelto no se etiqueta ni pide precio',
        (tester) async {
      await tester.pumpWidget(_buildTable(_makeLines(1)));
      await tester.pump();

      expect(find.byKey(const Key('purchaseItemWillCreateTag')), findsNothing);
      expect(find.byKey(const Key('purchaseItemSalePrice-prod-0')), findsNothing);
    });

    testWidgets('escribir el precio de venta lo reporta a la pantalla',
        (tester) async {
      final changes = <(String, double)>[];
      await tester.pumpWidget(_buildTable(
        [
          PurchaseDraftLine(
            item: _item('draft-1', 'Leche Lala 1L', unitCostMxn: 18.5),
            salePriceMxn: 25.90,
          ),
        ],
        onSalePriceChanged: (id, price) => changes.add((id, price)),
      ));
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('purchaseItemSalePrice-draft-1')), '32');
      await tester.pump();

      expect(changes.last, ('draft-1', 32.0));
    });

    testWidgets('buscar desde la fila la amarra al catálogo', (tester) async {
      final resolved = <(String, Product?)>[];
      await tester.pumpWidget(_buildTable(
        [
          PurchaseDraftLine(
            item: _item('draft-1', 'Leche Lala', unitCostMxn: 18.5),
            salePriceMxn: 25.90,
          ),
        ],
        catalog: [_product('p-leche', 'Leche Lala Entera 1L')],
        onResolve: (id, product) => resolved.add((id, product)),
      ));
      await tester.pumpAndSettle();

      // Al abrir la fila el campo toma el foco, así que ofrece el panel de
      // resultados del catálogo (los chips pasivos son para cuando no lo
      // tiene — un renglón de la factura que nadie ha tocado).
      await tester.tap(find.text('Leche Lala'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('productFieldResult_p-leche')));
      await tester.pumpAndSettle();

      expect(resolved.single.$1, 'draft-1');
      expect(resolved.single.$2?.id, 'p-leche');
    });
  });

  group('edición inline (iteración post-exploración CRF, Tarea 12.2.3)', () {
    testWidgets('tocar una fila la expande con los 3 campos editables',
        (tester) async {
      final lines = _makeLines(1);
      await tester.pumpWidget(_buildTable(lines));
      await tester.pump();

      expect(find.byKey(Key('purchaseItemEditName-${lines.first.id}')),
          findsNothing);

      await tester.tap(find.text('Producto 0'));
      await tester.pump();

      expect(find.byKey(Key('purchaseItemEditName-${lines.first.id}')),
          findsOneWidget);
      expect(find.byKey(Key('purchaseItemEditQty-${lines.first.id}')),
          findsOneWidget);
      expect(find.byKey(Key('purchaseItemEditCost-${lines.first.id}')),
          findsOneWidget);
    });

    testWidgets('confirmar la edición invoca onEdit con los valores nuevos',
        (tester) async {
      final lines = _makeLines(1);
      String? editedId;
      PurchaseOrderItem? edited;
      await tester.pumpWidget(_buildTable(lines, onEdit: (id, item) {
        editedId = id;
        edited = item;
      }));
      await tester.pump();

      await tester.tap(find.text('Producto 0'));
      await tester.pump();

      final id = lines.first.id;
      await tester.enterText(find.byKey(Key('purchaseItemEditQty-$id')), '9');
      await tester.enterText(
          find.byKey(Key('purchaseItemEditCost-$id')), '15.50');
      await tester.tap(find.byKey(Key('purchaseItemEditConfirm-$id')));
      await tester.pump();

      expect(editedId, id);
      expect(edited?.quantity, 9);
      expect(edited?.unitCostMxn, 15.50);
      expect(edited?.productName, 'Producto 0');
    });

    testWidgets('cancelar la edición no invoca onEdit y cierra el modo edición',
        (tester) async {
      final lines = _makeLines(1);
      var editCalled = false;
      await tester.pumpWidget(
          _buildTable(lines, onEdit: (_, __) => editCalled = true));
      await tester.pump();

      final id = lines.first.id;
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
      await tester.pumpWidget(_buildTable([
        PurchaseDraftLine(
          item: _item('p1', 'Tornillos', quantity: 5, unitCostMxn: 0),
          resolved: _product('p1', 'Tornillos'),
        ),
      ]));
      await tester.pump();

      expect(find.text('falta precio'), findsOneWidget);
      expect(find.text('falta cantidad'), findsNothing);
      expect(find.text('falta nombre'), findsNothing);
    });

    testWidgets('un producto sin nombre ni cantidad muestra ambos chips',
        (tester) async {
      await tester.pumpWidget(_buildTable([
        PurchaseDraftLine(
          item: _item('p1', '', quantity: 0, unitCostMxn: 20),
          resolved: _product('p1', 'Tornillos'),
        ),
      ]));
      await tester.pump();

      expect(find.text('falta nombre'), findsOneWidget);
      expect(find.text('falta cantidad'), findsOneWidget);
      expect(find.text('(sin nombre)'), findsOneWidget);
    });

    testWidgets('un producto completo no muestra ningún chip', (tester) async {
      await tester.pumpWidget(_buildTable(_makeLines(1)));
      await tester.pump();

      expect(find.textContaining('falta'), findsNothing);
    });

    testWidgets('"Quitar" en una fila incompleta no dispara el modo edición',
        (tester) async {
      String? removed;
      await tester.pumpWidget(_buildTable(
        [
          PurchaseDraftLine(
            item: _item('p1', 'Tornillos', quantity: 5, unitCostMxn: 0),
            resolved: _product('p1', 'Tornillos'),
          ),
        ],
        onRemove: (id) => removed = id,
      ));
      await tester.pump();

      await tester.tap(find.byTooltip('Quitar'));
      await tester.pump();

      expect(removed, 'p1');
      expect(find.byKey(const Key('purchaseItemEditName-p1')), findsNothing);
    });
  });
}
