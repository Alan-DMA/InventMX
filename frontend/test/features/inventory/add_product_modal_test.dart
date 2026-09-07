import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/add_product_modal.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockInventoryRepository extends Mock implements InventoryRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Product _makeCreatedProduct({String name = 'Coca-Cola 600ml'}) {
  return Product(
    id: 'prod-new',
    sku: 'NEX-NEW01',
    name: name,
    category: 'General',
    priceMxn: 18.0,
    costMxn: 0,
    stock: 5,
    reservedStock: 0,
    availableStock: 5,
    isActive: true,
    isOnCatalog: false,
    createdAt: DateTime(2026, 9, 6),
  );
}

/// Monta el AddProductModal directamente como pantalla para evitar
/// la complejidad de abrir un BottomSheet desde un botón en tests.
Widget _buildModal({
  MockInventoryRepository? repo,
  bool throwOnCreate = false,
}) {
  final mock = repo ?? MockInventoryRepository();

  // Stub getProducts — necesario porque InventoryNotifier lo llama en build()
  when(
    () => mock.getProducts(
      query: any(named: 'query'),
      category: any(named: 'category'),
      lowStock: any(named: 'lowStock'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    ),
  ).thenAnswer((_) async => const PaginatedProducts(
        items: [],
        total: 0,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      ));

  // Stub createProduct
  when(
    () => mock.createProduct(
      name: any(named: 'name'),
      priceMxn: any(named: 'priceMxn'),
      stock: any(named: 'stock'),
    ),
  ).thenAnswer((_) async {
    if (throwOnCreate) throw Exception('Error del servidor');
    return _makeCreatedProduct(
      name: _.namedArguments[const Symbol('name')] as String,
    );
  });

  return ProviderScope(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(mock),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(
        body: AddProductModal(),
      ),
    ),
  );
}

// Finder reutilizables
Finder get _nameField =>
    find.widgetWithText(TextFormField, 'Ej: Coca-Cola 600ml');

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    // Fallback requerido por mocktail para tipos nombrados
    registerFallbackValue(0.0);
  });

  // ── CA-02: botón deshabilitado con nombre vacío ───────────────────────────
  testWidgets('botón deshabilitado cuando nombre está vacío', (tester) async {
    await tester.pumpWidget(_buildModal());
    await tester.pump();

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Agregar producto'),
    );
    expect(btn.onPressed, isNull);
  });

  // ── CA-02: botón deshabilitado con precio 0 ──────────────────────────────
  testWidgets('botón deshabilitado cuando precio es 0', (tester) async {
    await tester.pumpWidget(_buildModal());
    await tester.pump();

    // Nombre válido, precio sin rellenar
    await tester.enterText(_nameField, 'Coca-Cola');
    await tester.pump();

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Agregar producto'),
    );
    expect(btn.onPressed, isNull);
  });

  // ── CA-02: botón habilitado con nombre y precio válidos ───────────────────
  testWidgets('botón habilitado con nombre ≥ 2 chars y precio > 0',
      (tester) async {
    await tester.pumpWidget(_buildModal());
    await tester.pump();

    await tester.enterText(_nameField, 'Coca-Cola');
    await tester.enterText(
      find.widgetWithText(TextFormField, '0.00'),
      '18',
    );
    await tester.pump();

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Agregar producto'),
    );
    expect(btn.onPressed, isNotNull);
  });

  // ── CA-01: stock default 0 si campo vacío ────────────────────────────────
  testWidgets('stock vacío envía 0 al crear el producto', (tester) async {
    final mock = MockInventoryRepository();

    when(
      () => mock.getProducts(
        query: any(named: 'query'),
        category: any(named: 'category'),
        lowStock: any(named: 'lowStock'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => const PaginatedProducts(
          items: [],
          total: 0,
          page: 1,
          pageSize: 20,
          totalPages: 1,
        ));

    when(
      () => mock.createProduct(
        name: any(named: 'name'),
        priceMxn: any(named: 'priceMxn'),
        stock: any(named: 'stock'),
      ),
    ).thenAnswer((_) async => _makeCreatedProduct());

    await tester.pumpWidget(_buildModal(repo: mock));
    await tester.pump();

    // Rellena nombre y precio, borra el stock (deja vacío)
    await tester.enterText(_nameField, 'Coca-Cola');
    await tester.enterText(find.widgetWithText(TextFormField, '0.00'), '18');
    // Borra el campo stock
    await tester.enterText(find.widgetWithText(TextFormField, '0'), '');
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar producto'));
    await tester.pumpAndSettle();

    // Verifica que se llamó createProduct con stock: 0
    verify(
      () => mock.createProduct(
        name: any(named: 'name'),
        priceMxn: any(named: 'priceMxn'),
        stock: 0,
      ),
    ).called(1);
  });

  // ── CA-03: error muestra banner sin cerrar el modal ───────────────────────
  testWidgets('error del servidor muestra banner sin cerrar el modal',
      (tester) async {
    await tester.pumpWidget(_buildModal(throwOnCreate: true));
    await tester.pump();

    await tester.enterText(_nameField, 'Coca-Cola');
    await tester.enterText(find.widgetWithText(TextFormField, '0.00'), '18');
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar producto'));
    await tester.pumpAndSettle();

    // El banner de error aparece
    expect(
      find.text('No se pudo guardar el producto. Intenta de nuevo.'),
      findsOneWidget,
    );
    // El modal sigue abierto (el campo Nombre sigue visible)
    expect(_nameField, findsOneWidget);
  });

  // ── CA-05: foco automático en campo Nombre al abrir ──────────────────────
  testWidgets('el campo Nombre tiene foco automático al montar el widget',
      (tester) async {
    await tester.pumpWidget(_buildModal());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // El TextFormField con hint 'Ej: Coca-Cola...' debe tener el foco
    final nameField = tester.widget<EditableText>(
      find.descendant(
        of: _nameField,
        matching: find.byType(EditableText),
      ),
    );
    expect(nameField.focusNode.hasFocus, isTrue);
  });

  // ── CA-07: indicador de carga durante la petición ────────────────────────
  testWidgets('botón muestra CircularProgressIndicator mientras guarda',
      (tester) async {
    final mock = MockInventoryRepository();
    final completer = Completer<Product>();

    when(
      () => mock.getProducts(
        query: any(named: 'query'),
        category: any(named: 'category'),
        lowStock: any(named: 'lowStock'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => const PaginatedProducts(
          items: [],
          total: 0,
          page: 1,
          pageSize: 20,
          totalPages: 1,
        ));

    when(
      () => mock.createProduct(
        name: any(named: 'name'),
        priceMxn: any(named: 'priceMxn'),
        stock: any(named: 'stock'),
      ),
    ).thenAnswer((_) => completer.future);

    await tester.pumpWidget(_buildModal(repo: mock));
    await tester.pump();

    await tester.enterText(_nameField, 'Coca-Cola');
    await tester.enterText(find.widgetWithText(TextFormField, '0.00'), '18');
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar producto'));
    await tester.pump(); // Un frame — el submit se inicia

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Agregar producto'), findsNothing);
  });

  // ── CA-06: secuencia de foco Nombre → Precio → Stock ─────────────────────
  testWidgets('el foco avanza de Nombre a Precio al pulsar Siguiente',
      (tester) async {
    await tester.pumpWidget(_buildModal());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Foco inicial en Nombre
    final nameEditable = tester.widget<EditableText>(
      find.descendant(of: _nameField, matching: find.byType(EditableText)),
    );
    expect(nameEditable.focusNode.hasFocus, isTrue);

    // Envía "next" desde el campo Nombre
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    // El foco debe estar ahora en el campo Precio (hintText '0.00')
    final priceEditable = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, '0.00'),
        matching: find.byType(EditableText),
      ),
    );
    expect(priceEditable.focusNode.hasFocus, isTrue);
  });
}
