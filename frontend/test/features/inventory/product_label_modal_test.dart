import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/product_label_modal.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Product _makeProduct() => Product(
      id: 'prod-001',
      sku: 'NEX-B0001',
      barcode: '7501055300018',
      name: 'Coca-Cola 600ml',
      category: 'Bebidas',
      priceMxn: 18.0,
      costMxn: 11.0,
      stock: 48,
      reservedStock: 0,
      availableStock: 48,
      isActive: true,
      isOnCatalog: true,
      createdAt: DateTime(2026, 9, 1),
    );

// El modal no usa providers — se puede montar directamente sin ProviderScope
Widget _buildWidget(Product product) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: ProductLabelModal(product: product)),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Nombre, SKU y precio visibles en la etiqueta ──────────────────────────
  testWidgets('nombre, SKU y precio MXN son visibles en la preview',
      (tester) async {
    await tester.pumpWidget(_buildWidget(_makeProduct()));
    await tester.pump();

    expect(find.text('Coca-Cola 600ml'), findsWidgets); // título modal + etiqueta
    expect(find.text('NEX-B0001'), findsOneWidget);
    expect(find.text('\$18.00 MXN'), findsOneWidget);
  });

  // ── Código de barras visible ───────────────────────────────────────────────
  testWidgets('código de barras numérico visible en la preview', (tester) async {
    await tester.pumpWidget(_buildWidget(_makeProduct()));
    await tester.pump();

    expect(find.text('7501055300018'), findsOneWidget);
  });

  // ── Selector de copias funciona ────────────────────────────────────────────
  testWidgets('selector de copias incrementa y decrementa', (tester) async {
    await tester.pumpWidget(_buildWidget(_makeProduct()));
    await tester.pump();

    // Valor inicial
    expect(find.text('1'), findsOneWidget);

    // Incrementa
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    // Decrementa
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    // No baja de 1
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });
}
