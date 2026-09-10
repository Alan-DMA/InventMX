import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/import_repository.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/presentation/gondola_scan_screen.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/scan_result_card.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockImportRepository extends Mock implements ImportRepository {}

class MockInventoryRepository extends Mock implements InventoryRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _cocaColaLookup = EanLookupResult(
  barcode: '7501055300018',
  name: 'Coca-Cola 600ml',
  category: 'Bebidas',
  source: 'SEED_CATALOG',
);

// ---------------------------------------------------------------------------
// Helper de montaje
// ---------------------------------------------------------------------------

void _stubInventoryRepo(MockInventoryRepository inventoryRepo) {
  when(() => inventoryRepo.getProducts(
        query: any(named: 'query'),
        category: any(named: 'category'),
        lowStock: any(named: 'lowStock'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      )).thenAnswer((_) async => const PaginatedProducts(
        items: [],
        total: 0,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      ));

  when(() => inventoryRepo.createProduct(
        name: any(named: 'name'),
        priceMxn: any(named: 'priceMxn'),
        stock: any(named: 'stock'),
      )).thenAnswer((_) async => throw Exception('not needed'));
}

Widget _buildScreen({
  required MockImportRepository importRepo,
  required MockInventoryRepository inventoryRepo,
}) {
  return ProviderScope(
    overrides: [
      importRepositoryProvider.overrideWithValue(importRepo),
      inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const GondolaScanScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockImportRepository importRepo;
  late MockInventoryRepository inventoryRepo;

  setUp(() {
    importRepo = MockImportRepository();
    inventoryRepo = MockInventoryRepository();
    _stubInventoryRepo(inventoryRepo);
  });

  setUpAll(() {
    registerFallbackValue(0.0);
    registerFallbackValue(0);
  });

  // ── CA-06: pantalla muestra overlay de cámara o placeholder ─────────────
  testWidgets('GondolaScanScreen se monta y muestra AppBar correctamente',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      importRepo: importRepo,
      inventoryRepo: inventoryRepo,
    ));
    await tester.pump();

    // AppBar con título "Modo Góndola"
    expect(find.text('Modo Góndola'), findsOneWidget);
    // Botón de linterna presente
    expect(find.byIcon(Icons.flash_on_rounded), findsOneWidget);
  });

  // ── CA-07: EAN conocido autocompleta nombre del producto ─────────────────
  testWidgets(
      'ScanResultCard con EAN conocido muestra nombre autocompletado del catálogo',
      (tester) async {
    // Montamos ScanResultCard directamente — simula que el lookup encontró el EAN
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ScanResultCard(
            barcode: '7501055300018',
            suggestedName: _cocaColaLookup.name,
            suggestedCategory: _cocaColaLookup.category,
            onConfirm: (_, __, ___) {},
            onDismiss: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    // El nombre del catálogo aparece en el campo
    expect(
        find.widgetWithText(TextFormField, 'Coca-Cola 600ml'), findsOneWidget);
    // El badge de categoría sugerida está presente
    expect(find.text('Bebidas'), findsOneWidget);
    // El header indica producto encontrado
    expect(find.text('Producto encontrado en catálogo'), findsOneWidget);
  });

  // ── CA-08: EAN desconocido muestra campo nombre editable vacío ───────────
  testWidgets(
      'ScanResultCard sin nombre sugerido muestra campo nombre vacío y editable',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ScanResultCard(
            barcode: '1234567890123',
            suggestedName: null,
            suggestedCategory: null,
            onConfirm: (_, __, ___) {},
            onDismiss: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    // Header de código no registrado
    expect(find.text('Código no registrado'), findsOneWidget);
    // Campo nombre vacío y editable
    final nameFields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .where((f) => f.controller?.text == '')
        .toList();
    expect(nameFields.isNotEmpty, isTrue);
  });

  // ── CA-09: confirmar producto llama onConfirm con los datos ──────────────
  testWidgets('confirmar en ScanResultCard llama onConfirm con nombre y precio',
      (tester) async {
    String? confirmedName;
    double? confirmedPrice;
    int? confirmedStock;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScanResultCard(
              barcode: '7501055300018',
              suggestedName: 'Coca-Cola 600ml',
              suggestedCategory: 'Bebidas',
              onConfirm: (name, price, stock) {
                confirmedName = name;
                confirmedPrice = price;
                confirmedStock = stock;
              },
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Ingresa precio
    await tester.enterText(
      find.widgetWithText(TextFormField, '').first,
      '18.00',
    );
    await tester.pump();

    // Toca el botón confirmar
    await tester
        .ensureVisible(find.widgetWithText(ElevatedButton, 'Agregar producto'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar producto'));
    await tester.pump();

    expect(confirmedName, equals('Coca-Cola 600ml'));
    expect(confirmedPrice, equals(18.0));
    expect(confirmedStock, isNotNull);
  });

  // ── CA-10: botón onDismiss cierra la card ────────────────────────────────
  testWidgets('botón cerrar en ScanResultCard llama onDismiss', (tester) async {
    bool dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ScanResultCard(
            barcode: '7501055300018',
            suggestedName: 'Coca-Cola 600ml',
            suggestedCategory: 'Bebidas',
            onConfirm: (_, __, ___) {},
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    await tester.pump();

    // Toca el botón de cierre (×)
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(dismissed, isTrue);
  });
}
