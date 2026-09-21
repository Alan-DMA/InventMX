import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/purchases/domain/purchase_order.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/purchase_order_card.dart';

/// La fecha de la tarjeta — antes mostraba `createdAt` sin etiqueta, así que
/// la fecha esperada de entrega que el usuario elegía al crear la orden no
/// aparecía en ningún lado y parecía que no se guardaba (hallazgo de QA,
/// Sep 19). Ahora cada estado enseña la fecha que le sirve, con su nombre.
PurchaseOrder _order({
  PurchaseOrderStatus status = PurchaseOrderStatus.confirmed,
  DateTime? expectedDeliveryDate,
  DateTime? receivedDate,
}) =>
    PurchaseOrder(
      id: 'po-1',
      folio: 'OC-2026-000001',
      supplierId: 'sup-1',
      supplierName: 'Distribuidora Bimbo Norte',
      status: status,
      items: const [
        PurchaseOrderItem(
          productId: 'p1',
          productName: 'Pan Bimbo Grande',
          quantity: 6,
          unitCostMxn: 52,
        ),
      ],
      subtotalMxn: 312,
      taxMxn: 0,
      totalMxn: 312,
      createdAt: DateTime(2026, 9, 10),
      expectedDeliveryDate: expectedDeliveryDate,
      receivedDate: receivedDate,
    );

Future<void> _pump(WidgetTester tester, PurchaseOrder order) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: PurchaseOrderCard(
          order: order,
          onTap: () {},
          onReceive: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pendiente con fecha de entrega muestra cuándo llega',
      (tester) async {
    await _pump(tester, _order(expectedDeliveryDate: DateTime(2026, 9, 15)));

    expect(find.text('Llega: 15 sep'), findsOneWidget);
  });

  testWidgets('recibida muestra la fecha en que llegó, no la de creación',
      (tester) async {
    await _pump(
      tester,
      _order(
        status: PurchaseOrderStatus.received,
        expectedDeliveryDate: DateTime(2026, 9, 15),
        receivedDate: DateTime(2026, 9, 16),
      ),
    );

    expect(find.text('Recibida: 16 sep'), findsOneWidget);
  });

  testWidgets('parcial sin fecha esperada muestra la última entrega',
      (tester) async {
    await _pump(
      tester,
      _order(
        status: PurchaseOrderStatus.partiallyReceived,
        receivedDate: DateTime(2026, 9, 14),
      ),
    );

    expect(find.text('Última entrega: 14 sep'), findsOneWidget);
  });

  testWidgets('sin ninguna fecha de entrega cae a la de creación, nombrada',
      (tester) async {
    await _pump(tester, _order());

    expect(find.text('Creada: 10 sep'), findsOneWidget);
  });

  testWidgets('una fecha de otro año conserva el año', (tester) async {
    await _pump(tester, _order(expectedDeliveryDate: DateTime(2025, 12, 28)));

    expect(find.text('Llega: 28 dic 2025'), findsOneWidget);
  });
}
