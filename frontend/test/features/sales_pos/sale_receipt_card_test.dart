import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_state.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';
import 'package:nexus_app/features/sales_pos/presentation/widgets/sale_receipt_card.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

CheckoutResult _makeResult({double changeGivenMxn = 39.0}) {
  return CheckoutResult(
    saleId: 'sale-001',
    folio: 'NV-2026-001547',
    totalMxn: 61.0,
    totalPaidMxn: 100.0,
    changeGivenMxn: changeGivenMxn,
    items: const [
      CartItem(
        id: 'cart-1',
        productId: 'prod-1',
        name: 'Coca-Cola 600ml',
        unitPriceMxn: 18.0,
        quantity: 2,
      ),
      CartItem(
        id: 'cart-2',
        productId: 'prod-2',
        name: 'Harina PAN 1kg',
        unitPriceMxn: 25.0,
        quantity: 1,
      ),
    ],
    payments: const [
      PaymentEntry(
        id: 'pay-1',
        method: PaymentMethodMxn.cashMxn,
        amountMxn: 100.0,
      ),
    ],
    cashierName: 'Ana García',
    completedAt: DateTime(2026, 7, 2, 14, 35),
  );
}

Widget _buildCard(CheckoutResult result) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: SaleReceiptCard(
        result: result,
        businessName: 'Abastos El Sol',
        warehouseName: 'Sucursal Centro',
        footerMessage: '¡Gracias por su compra!',
        pageBackground: Colors.black,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets('muestra encabezado del comercio, folio y cajero',
      (tester) async {
    await tester.pumpWidget(_buildCard(_makeResult()));

    expect(find.text('Abastos El Sol'), findsOneWidget);
    expect(find.text('Sucursal Centro'), findsOneWidget);
    expect(find.text('NV-2026-001547'), findsOneWidget);
    expect(find.text('Ana García'), findsOneWidget);
  });

  testWidgets('lista cada ítem con cantidad y subtotal', (tester) async {
    await tester.pumpWidget(_buildCard(_makeResult()));

    expect(find.text('Coca-Cola 600ml x2'), findsOneWidget);
    expect(find.text('\$36.00'), findsOneWidget);
    expect(find.text('Harina PAN 1kg x1'), findsOneWidget);
    expect(find.text('\$25.00'), findsOneWidget);
  });

  testWidgets('muestra el total y el desglose de pago', (tester) async {
    await tester.pumpWidget(_buildCard(_makeResult()));

    expect(find.text('Total'), findsOneWidget);
    expect(find.text('\$61.00'), findsOneWidget);
    expect(find.text('Efectivo'), findsOneWidget);
    expect(find.text('\$100.00'), findsOneWidget);
  });

  testWidgets('muestra el vuelto cuando es mayor a cero', (tester) async {
    await tester.pumpWidget(_buildCard(_makeResult(changeGivenMxn: 39.0)));

    expect(find.text('Vuelto'), findsOneWidget);
    expect(find.text('\$39.00'), findsOneWidget);
  });

  testWidgets('oculta el vuelto cuando el pago es exacto', (tester) async {
    await tester.pumpWidget(_buildCard(_makeResult(changeGivenMxn: 0.0)));

    expect(find.text('Vuelto'), findsNothing);
  });

  testWidgets('muestra el mensaje de pie configurado', (tester) async {
    await tester.pumpWidget(_buildCard(_makeResult()));

    expect(find.text('¡Gracias por su compra!'), findsOneWidget);
  });
}
