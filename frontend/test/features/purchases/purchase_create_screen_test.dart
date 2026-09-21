import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/purchases/presentation/purchase_create_screen.dart';

class _MockInventoryRepository extends Mock implements InventoryRepository {}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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

/// `ProductPickerField` (Compras) busca contra `inventoryProvider.products` —
/// se necesita un catálogo fake para que "Pan de caja"/"Producto A"/
/// "Producto B" sean resolvables en vez de texto libre (ver retome de la
/// Tarea 11.2/12.2 en `registro_implementacion.md`).
final _catalog = [
  _product('p-pan', 'Pan de caja'),
  _product('p-a', 'Producto A'),
  _product('p-b', 'Producto B'),
];

/// Monta `PurchaseCreateScreen` y avanza el reloj falso más allá del
/// `_fakeDelay` (500 ms) del mock ANTES de cualquier `pumpAndSettle()` — la
/// pantalla no muestra un spinner indeterminado mientras carga proveedores,
/// así que `pumpAndSettle()` podría "asentarse" antes de que el Timer del
/// mock llegue a disparar, dejándolo pendiente al terminar el test.
Future<void> _pumpReady(WidgetTester tester) async {
  final mockInventory = _MockInventoryRepository();
  when(
    () => mockInventory.getProducts(
      query: any(named: 'query'),
      category: any(named: 'category'),
      lowStock: any(named: 'lowStock'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    ),
  ).thenAnswer((_) async => PaginatedProducts(
        items: _catalog,
        total: _catalog.length,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      ));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [inventoryRepositoryProvider.overrideWithValue(mockInventory)],
      child:
          MaterialApp(theme: AppTheme.dark, home: const PurchaseCreateScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

/// Busca [name] en `ProductField` y toca el resultado del catálogo fake para
/// amarrar la línea a un producto real.
///
/// `pumpAndSettle` y no `pump`: el panel de resultados entra con `AnimatedSize`
/// (180 ms) y a un solo frame todavía no tiene alto — el toque caería fuera.
Future<void> _pickProduct(
    WidgetTester tester, String productId, String name) async {
  await tester.enterText(find.byKey(const Key('purchaseEntryNameField')), name);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('productFieldResult_$productId')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('el botón de crear está deshabilitado sin proveedor ni productos',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Crear orden de compra'),
    );
    expect(btn.onPressed, isNull);
    expect(find.text('Aún no agregas productos a esta orden.'), findsOneWidget);
  });

  testWidgets(
      'un producto que no existe entra como "Se creará", sin abrir ningún formulario',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    await tester.enterText(
        find.byKey(const Key('purchaseEntryQtyField')), '10');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryCostField')), '25');
    // Texto libre, sin tocar ningún resultado del catálogo.
    await tester.enterText(
        find.byKey(const Key('purchaseEntryNameField')), 'Chiles en vinagre');
    await tester.pump();

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Agregar'),
    );
    expect(btn.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pumpAndSettle();

    // Queda en la tabla marcado como producto por crear, con su precio de
    // venta sugerido (25 × 1.4) — y el botón de confirmar lo anuncia.
    expect(find.byKey(const Key('purchaseItemWillCreateTag')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
              find.byKey(const Key('purchaseItemSalePrice-draft-1')))
          .controller!
          .text,
      '35.00',
    );
    expect(
      find.widgetWithText(ElevatedButton, 'Crear orden y 1 producto nuevo'),
      findsOneWidget,
    );
  });

  testWidgets(
      '"Agregar" con un producto del catálogo lo añade resuelto y limpia el formulario',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    await _pickProduct(tester, 'p-pan', 'Pan de caja');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryQtyField')), '10');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryCostField')), '25');
    await tester.pump();

    expect(find.text('Subtotal: \$250.00'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pump();

    // La línea aparece en la tabla de resumen...
    expect(find.text('Pan de caja'), findsOneWidget);
    expect(find.text('10 × \$25.00'), findsOneWidget);
    // ...y el formulario de captura queda limpio, listo para otra línea.
    expect(find.byKey(const Key('productFieldUnlinkButton')), findsNothing);
    expect(find.text('Aún no agregas productos a esta orden.'), findsNothing);
  });

  testWidgets('quitar una línea de la tabla de resumen la elimina del total',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    await _pickProduct(tester, 'p-pan', 'Pan de caja');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryQtyField')), '10');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryCostField')), '25');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pump();

    expect(find.text('Pan de caja'), findsOneWidget);

    await tester.tap(find.byTooltip('Quitar'));
    await tester.pump();

    expect(find.text('Pan de caja'), findsNothing);
    expect(find.text('Aún no agregas productos a esta orden.'), findsOneWidget);
  });

  testWidgets('cada nueva línea se agrega arriba de la tabla, no abajo',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    Future<void> addLine(String productId, String name, String qty, String cost) async {
      await _pickProduct(tester, productId, name);
      await tester.enterText(
          find.byKey(const Key('purchaseEntryQtyField')), qty);
      await tester.enterText(
          find.byKey(const Key('purchaseEntryCostField')), cost);
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
      await tester.pump();
    }

    await addLine('p-a', 'Producto A', '1', '10');
    await addLine('p-b', 'Producto B', '1', '10');

    // "Producto B" (agregado después) debe quedar arriba de "Producto A".
    final yA = tester.getTopLeft(find.text('Producto A')).dy;
    final yB = tester.getTopLeft(find.text('Producto B')).dy;
    expect(yB, lessThan(yA));
  });

  testWidgets(
      '"Agregar" cierra el teclado para que la fila recién agregada no quede tapada',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    await tester.enterText(
        find.byKey(const Key('purchaseEntryQtyField')), '10');
    // `enterText` deja el campo enfocado — simula el teclado abierto.
    await tester.enterText(
        find.byKey(const Key('purchaseEntryCostField')), '25');
    await tester.pump();
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((e) => e.focusNode.hasFocus),
      isTrue,
    );

    await _pickProduct(tester, 'p-pan', 'Pan de caja');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pumpAndSettle();

    // Ningún campo de texto conserva el foco — el teclado se cierra.
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((e) => e.focusNode.hasFocus),
      isFalse,
    );
  });

  testWidgets(
      'tener productos pero ningún proveedor mantiene el botón de crear deshabilitado',
      (tester) async {
    _setPhoneViewport(tester);
    await _pumpReady(tester);

    await _pickProduct(tester, 'p-pan', 'Pan de caja');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryQtyField')), '10');
    await tester.enterText(
        find.byKey(const Key('purchaseEntryCostField')), '25');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pump();

    // Selección del proveedor vía el overlay de `DropdownButtonFormField` se
    // deja fuera de este test (interacción del framework, no lógica propia)
    // — `createOrder` ya está cubierto en `purchases_provider_test.dart`.
    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Crear orden de compra'),
    );
    expect(btn.onPressed, isNull);
  });
}
