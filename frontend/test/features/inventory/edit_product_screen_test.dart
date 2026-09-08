import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/edit_product_screen.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockInventoryRepository extends Mock implements InventoryRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Product _baseProduct({
  String name = 'Coca-Cola 600ml',
  double price = 18.0,
  double cost = 11.50,
  String category = 'Bebidas',
  String? barcode = '7501055300018',
  int minStockAlert = 10,
  bool isActive = true,
}) {
  return Product(
    id: 'prod-001',
    sku: 'NEX-B0001',
    name: name,
    category: category,
    priceMxn: price,
    costMxn: cost,
    stock: 48,
    reservedStock: 0,
    availableStock: 48,
    minStockAlert: minStockAlert,
    barcode: barcode,
    isActive: isActive,
    isOnCatalog: false,
    createdAt: DateTime(2026, 9, 1),
  );
}

/// Stub mínimo para getProducts — requerido porque InventoryNotifier
/// llama a _load() en su build(), lo que invoca getProducts.
void _stubGetProducts(MockInventoryRepository mock, {List<Product>? products}) {
  when(
    () => mock.getProducts(
      query: any(named: 'query'),
      category: any(named: 'category'),
      lowStock: any(named: 'lowStock'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    ),
  ).thenAnswer((_) async => PaginatedProducts(
        items: products ?? [_baseProduct()],
        total: products?.length ?? 1,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      ));
}

/// Monta EditProductScreen con overrides de provider.
Widget _buildScreen({
  required Product product,
  MockInventoryRepository? repo,
  bool throwOnUpdate = false,
}) {
  final mock = repo ?? MockInventoryRepository();
  _stubGetProducts(mock, products: [product]);

  when(
    () => mock.updateProduct(
      productId: any(named: 'productId'),
      name: any(named: 'name'),
      priceMxn: any(named: 'priceMxn'),
      costMxn: any(named: 'costMxn'),
      category: any(named: 'category'),
      barcode: any(named: 'barcode'),
      minStockAlert: any(named: 'minStockAlert'),
      imageUrl: any(named: 'imageUrl'),
      isActive: any(named: 'isActive'),
    ),
  ).thenAnswer((_) async {
    if (throwOnUpdate) throw Exception('Error del servidor');
    return product.copyWith(
      name: _.namedArguments[const Symbol('name')] as String? ?? product.name,
    );
  });

  // Stub getMovements (requerido por kardex_provider si se inicializa)
  when(
    () => mock.getMovements(
      productId: any(named: 'productId'),
      movementType: any(named: 'movementType'),
      dateFrom: any(named: 'dateFrom'),
      dateTo: any(named: 'dateTo'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    ),
  ).thenAnswer((_) async => const PaginatedMovements(
        items: [],
        total: 0,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      ));

  return ProviderScope(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(mock),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: EditProductScreen(product: product),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(0.0);
    registerFallbackValue(0);
    registerFallbackValue(false);
  });

  // ── CA-01: campos prellenados con datos actuales ──────────────────────────
  testWidgets('campos prellenados con los datos actuales del producto',
      (tester) async {
    final p = _baseProduct();
    await tester.pumpWidget(_buildScreen(product: p));
    await tester.pump();

    // Nombre
    expect(find.widgetWithText(TextFormField, p.name), findsOneWidget);
    // Precio
    expect(find.widgetWithText(TextFormField, p.priceMxn.toStringAsFixed(2)),
        findsOneWidget);
    // Costo
    expect(find.widgetWithText(TextFormField, p.costMxn.toStringAsFixed(2)),
        findsOneWidget);
    // Barcode
    expect(find.widgetWithText(TextFormField, p.barcode!), findsOneWidget);
    // Categoría — ahora es DropdownButtonFormField; verifica que el texto
    // de la categoría actual sea visible en pantalla
    expect(find.text(p.category), findsWidgets);
    // Stock mínimo
    expect(find.widgetWithText(TextFormField, p.minStockAlert.toString()),
        findsOneWidget);
  });

  // ── CA-02: SKU visible pero no editable ───────────────────────────────────
  testWidgets('SKU se muestra pero su campo está deshabilitado',
      (tester) async {
    final p = _baseProduct();
    await tester.pumpWidget(_buildScreen(product: p));
    await tester.pump();

    // Encontrar el TextFormField que contiene el SKU
    final skuFields =
        tester.widgetList<TextFormField>(find.byType(TextFormField)).where((f) {
      final controller = f.controller;
      return controller != null && controller.text == p.sku ||
          f.initialValue == p.sku;
    });
    expect(skuFields.isNotEmpty, isTrue);

    // El campo SKU está deshabilitado
    final skuField = skuFields.first;
    expect(skuField.enabled, isFalse);
  });

  // ── CA-03: botón Guardar deshabilitado con nombre vacío ───────────────────
  testWidgets('Guardar deshabilitado cuando nombre queda vacío',
      (tester) async {
    final p = _baseProduct();
    await tester.pumpWidget(_buildScreen(product: p));
    await tester.pump();

    // Borra el nombre
    await tester.enterText(find.widgetWithText(TextFormField, p.name), '');
    await tester.pump();

    final btn = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Guardar'),
    );
    expect(btn.onPressed, isNull);
  });

  // ── CA-03: botón Guardar deshabilitado con precio 0 ───────────────────────
  testWidgets('Guardar deshabilitado cuando precio queda en 0', (tester) async {
    final p = _baseProduct();
    await tester.pumpWidget(_buildScreen(product: p));
    await tester.pump();

    // Borra el precio
    await tester.enterText(
        find.widgetWithText(TextFormField, p.priceMxn.toStringAsFixed(2)), '0');
    await tester.pump();

    final btn = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Guardar'),
    );
    expect(btn.onPressed, isNull);
  });

  // ── CA-04: guardar exitoso llama updateProduct y completa el flujo ─────────
  testWidgets(
      'guardar exitoso llama updateProduct con los datos del formulario',
      (tester) async {
    final p = _baseProduct();
    final mock = MockInventoryRepository();
    _stubGetProducts(mock, products: [p]);

    when(
      () => mock.updateProduct(
        productId: any(named: 'productId'),
        name: any(named: 'name'),
        priceMxn: any(named: 'priceMxn'),
        costMxn: any(named: 'costMxn'),
        category: any(named: 'category'),
        barcode: any(named: 'barcode'),
        minStockAlert: any(named: 'minStockAlert'),
        imageUrl: any(named: 'imageUrl'),
        isActive: any(named: 'isActive'),
      ),
    ).thenAnswer((_) async => p.copyWith(name: 'Coca-Cola 1L'));

    when(
      () => mock.getMovements(
        productId: any(named: 'productId'),
        movementType: any(named: 'movementType'),
        dateFrom: any(named: 'dateFrom'),
        dateTo: any(named: 'dateTo'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => const PaginatedMovements(
          items: [],
          total: 0,
          page: 1,
          pageSize: 20,
          totalPages: 1,
        ));

    await tester.pumpWidget(_buildScreen(product: p, repo: mock));
    await tester.pump();

    // Edita el nombre
    await tester.enterText(
        find.widgetWithText(TextFormField, p.name), 'Coca-Cola 1L');
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Guardar'));
    await tester.pump();
    await tester
        .pump(const Duration(milliseconds: 700)); // supera el delay 600ms

    // Verifica que updateProduct fue invocado con el nombre correcto
    verify(() => mock.updateProduct(
          productId: p.id,
          name: 'Coca-Cola 1L',
          priceMxn: any(named: 'priceMxn'),
          costMxn: any(named: 'costMxn'),
          category: any(named: 'category'),
          barcode: any(named: 'barcode'),
          minStockAlert: any(named: 'minStockAlert'),
          imageUrl: any(named: 'imageUrl'),
          isActive: any(named: 'isActive'),
        )).called(1);

    // El indicador de carga desaparece — flujo completado
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  // ── CA-05: error muestra banner sin cerrar pantalla ───────────────────────
  testWidgets('error del servidor muestra banner sin cerrar la pantalla',
      (tester) async {
    final p = _baseProduct();
    await tester.pumpWidget(_buildScreen(product: p, throwOnUpdate: true));
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Guardar'));
    await tester.pumpAndSettle();

    // Banner de error visible
    expect(
      find.textContaining('No se pudo guardar'),
      findsOneWidget,
    );
    // La pantalla sigue abierta — el título del AppBar sigue ahí
    expect(find.text('Editar producto'), findsOneWidget);
  });

  // ── CA-06: dropdown de categoría selecciona correctamente ────────────────
  testWidgets('seleccionar categoría en el dropdown actualiza la selección',
      (tester) async {
    final p = _baseProduct(category: 'Abarrotes');
    final mock = MockInventoryRepository();
    _stubGetProducts(mock, products: [
      p,
      _baseProduct(category: 'Bebidas'),
      _baseProduct(category: 'Lácteos'),
    ]);

    when(
      () => mock.updateProduct(
        productId: any(named: 'productId'),
        name: any(named: 'name'),
        priceMxn: any(named: 'priceMxn'),
        costMxn: any(named: 'costMxn'),
        category: any(named: 'category'),
        barcode: any(named: 'barcode'),
        minStockAlert: any(named: 'minStockAlert'),
        imageUrl: any(named: 'imageUrl'),
        isActive: any(named: 'isActive'),
      ),
    ).thenAnswer((_) async => p);

    when(
      () => mock.getMovements(
        productId: any(named: 'productId'),
        movementType: any(named: 'movementType'),
        dateFrom: any(named: 'dateFrom'),
        dateTo: any(named: 'dateTo'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => const PaginatedMovements(
          items: [],
          total: 0,
          page: 1,
          pageSize: 20,
          totalPages: 1,
        ));

    await tester.pumpWidget(ProviderScope(
      overrides: [inventoryRepositoryProvider.overrideWithValue(mock)],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: EditProductScreen(product: p),
      ),
    ));
    await tester.pumpAndSettle();

    // El dropdown existe y muestra la categoría inicial del producto
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

    // Abre el dropdown
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    // Selecciona "Bebidas" del menú desplegado
    await tester.tap(
      find
          .descendant(
            of: find.byType(DropdownMenuItem<String>),
            matching: find.text('Bebidas'),
          )
          .first,
    );
    await tester.pumpAndSettle();

    // El dropdown ahora refleja "Bebidas"
    expect(find.text('Bebidas'), findsWidgets);
  });

  // ── CA-07: switch activo/inactivo cambia visualmente ──────────────────────
  testWidgets('switch activo/inactivo cambia su estado al tocarlo',
      (tester) async {
    final p = _baseProduct(isActive: true);
    await tester.pumpWidget(_buildScreen(product: p));
    await tester.pump();

    // Estado inicial: ON
    final switchBefore = tester.widget<Switch>(find.byType(Switch));
    expect(switchBefore.value, isTrue);

    // Scroll hasta el switch (está al fondo de la pantalla)
    await tester.ensureVisible(find.byType(Switch));
    await tester.pump();

    // Tap al switch
    await tester.tap(find.byType(Switch), warnIfMissed: false);
    await tester.pump();

    // Estado después: OFF
    final switchAfter = tester.widget<Switch>(find.byType(Switch));
    expect(switchAfter.value, isFalse);
  });

  // ── CA-08: botón Cambiar foto muestra SnackBar placeholder ────────────────
  testWidgets('botón Cambiar foto muestra SnackBar de próximamente',
      (tester) async {
    final p = _baseProduct();
    await tester.pumpWidget(_buildScreen(product: p));
    await tester.pump();

    await tester.tap(find.text('Cambiar foto'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('próximamente'),
      findsOneWidget,
    );
  });
}
