import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/purchases/data/purchases_repository.dart';
import 'package:nexus_app/features/purchases/domain/account_payable.dart';
import 'package:nexus_app/features/purchases/domain/purchase_order.dart';
import 'package:nexus_app/features/purchases/presentation/purchase_order_detail_screen.dart';
import 'package:nexus_app/features/purchases/presentation/purchases_provider.dart';

class _MockPurchasesRepository extends Mock implements PurchasesRepository {}

/// El SnackBar de confirmación vive 4 s: si el test termina antes, su timer
/// se dispara dentro del siguiente y lo hace fallar por contaminación.
Future<void> _drainSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// Repositorio del último `_pump` — las pruebas de cancelación verifican
/// contra él qué se le pidió al backend.
late _MockPurchasesRepository _lastRepo;

PurchaseOrderItem _item(
  String name, {
  int quantity = 12,
  int received = 0,
  double unitCost = 18.50,
}) =>
    PurchaseOrderItem(
      id: 'item-$name',
      productId: 'prod-$name',
      productName: name,
      quantity: quantity,
      quantityReceived: received,
      unitCostMxn: unitCost,
    );

PurchaseOrder _order({
  PurchaseOrderStatus status = PurchaseOrderStatus.confirmed,
  List<PurchaseOrderItem>? items,
  DateTime? expectedDeliveryDate,
  DateTime? receivedDate,
  String? invoiceReference,
  String? notes,
  double taxMxn = 0,
}) =>
    PurchaseOrder(
      id: 'po-1',
      folio: 'OC-2026-000012',
      supplierId: 'sup-1',
      supplierName: 'Distribuidora Bimbo Norte',
      warehouseName: 'Almacén Principal',
      status: status,
      items: items ?? [_item('Coca Cola 600ml')],
      subtotalMxn: 222,
      taxMxn: taxMxn,
      totalMxn: 222 + taxMxn,
      createdAt: DateTime(2026, 9, 10),
      expectedDeliveryDate: expectedDeliveryDate,
      receivedDate: receivedDate,
      invoiceReference: invoiceReference,
      notes: notes,
    );

AccountPayable _payable({
  String? purchaseOrderId = 'po-1',
  double paid = 0,
}) =>
    AccountPayable(
      id: 'ap-1',
      supplierId: 'sup-1',
      supplierName: 'Distribuidora Bimbo Norte',
      purchaseOrderId: purchaseOrderId,
      folio: 'CXP-000008',
      originalAmountMxn: 222,
      paidAmountMxn: paid,
      status: AccountPayableStatus.pending,
      dueDate: DateTime(2026, 10, 16),
      createdAt: DateTime(2026, 9, 16),
      updatedAt: DateTime(2026, 9, 16),
    );

/// Monta el detalle con una orden "semilla" y un repositorio que devuelve
/// [live] — así se puede comprobar que la pantalla pinta la versión viva del
/// provider y no la copia con la que se abrió.
Future<void> _pump(
  WidgetTester tester, {
  required PurchaseOrder seed,
  PurchaseOrder? live,
  List<AccountPayable> payables = const [],
}) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = _MockPurchasesRepository();
  _lastRepo = repo;
  when(() => repo.cancelPurchaseOrder(
        purchaseOrderId: any(named: 'purchaseOrderId'),
        reason: any(named: 'reason'),
      )).thenAnswer((_) async => (live ?? seed));
  when(() => repo.listPurchaseOrders(
        search: any(named: 'search'),
        dateFrom: any(named: 'dateFrom'),
        dateTo: any(named: 'dateTo'),
      )).thenAnswer((_) async => [live ?? seed]);
  when(() => repo.listAccountsPayable(overdueOnly: any(named: 'overdueOnly')))
      .thenAnswer((_) async => AccountsPayableResult(
            items: payables,
            summary: const AccountsPayableSummary(
              totalPendingMxn: 0,
              totalPaidMxn: 0,
              overdueAmountMxn: 0,
              overdueCount: 0,
              pendingCount: 0,
            ),
          ));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [purchasesRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: PurchaseOrderDetailScreen(order: seed),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('la respuesta cambia según el estado', () {
    testWidgets('pendiente con fecha dice cuándo llega', (tester) async {
      await _pump(
        tester,
        seed: _order(expectedDeliveryDate: DateTime(2026, 9, 15)),
      );

      expect(find.text('Llega el 15 sep'), findsOneWidget);
    });

    testWidgets('pendiente sin fecha lo dice en vez de inventar una',
        (tester) async {
      await _pump(tester, seed: _order());

      expect(find.text('Sin fecha de entrega acordada'), findsOneWidget);
    });

    testWidgets('parcial dice cuántas piezas faltan', (tester) async {
      await _pump(
        tester,
        seed: _order(
          status: PurchaseOrderStatus.partiallyReceived,
          items: [
            _item('Coca Cola 600ml', quantity: 12, received: 6),
            _item('Pan Bimbo', quantity: 6, received: 6),
          ],
          receivedDate: DateTime(2026, 9, 14),
        ),
      );

      expect(find.text('Faltan 6 piezas por llegar'), findsOneWidget);
      expect(find.text('Llegó parte el 14 sep'), findsOneWidget);
    });

    testWidgets('una sola pieza faltante va en singular', (tester) async {
      await _pump(
        tester,
        seed: _order(
          status: PurchaseOrderStatus.partiallyReceived,
          items: [_item('Coca Cola 600ml', quantity: 12, received: 11)],
        ),
      );

      expect(find.text('Falta 1 pieza por llegar'), findsOneWidget);
    });

    testWidgets('recibida dice cuándo llegó completa', (tester) async {
      await _pump(
        tester,
        seed: _order(
          status: PurchaseOrderStatus.received,
          items: [_item('Coca Cola 600ml', quantity: 12, received: 12)],
          receivedDate: DateTime(2026, 9, 16),
        ),
      );

      expect(find.text('Recibida completa el 16 sep'), findsOneWidget);
    });

    testWidgets('cancelada lo dice sin rodeos', (tester) async {
      await _pump(tester, seed: _order(status: PurchaseOrderStatus.cancelled));

      expect(find.text('Orden cancelada'), findsOneWidget);
    });
  });

  group('avance por renglón', () {
    testWidgets('no aparece mientras nada ha llegado', (tester) async {
      await _pump(
        tester,
        seed: _order(expectedDeliveryDate: DateTime(2026, 9, 15)),
      );

      // Un "0 de 12" en cada línea de una orden que no ha recibido nada sería
      // ruido: la respuesta de arriba ya dijo cuándo llega.
      expect(find.textContaining('recibidas'), findsNothing);
      expect(find.text('Sin recibir'), findsNothing);
    });

    testWidgets('en una orden parcial distingue línea por línea',
        (tester) async {
      await _pump(
        tester,
        seed: _order(
          status: PurchaseOrderStatus.partiallyReceived,
          items: [
            _item('Coca Cola 600ml', quantity: 12, received: 6),
            _item('Pan Bimbo', quantity: 6, received: 6),
            _item('Jabón Zote', quantity: 4, received: 0),
          ],
        ),
      );

      expect(find.text('6 de 12 recibidas'), findsOneWidget);
      expect(find.text('Completa'), findsOneWidget);
      expect(find.text('Sin recibir'), findsOneWidget);
    });
  });

  group('cuenta por pagar', () {
    testWidgets('la CxP de esta orden se muestra con saldo y vencimiento',
        (tester) async {
      await _pump(
        tester,
        seed: _order(status: PurchaseOrderStatus.received),
        payables: [_payable()],
      );

      expect(find.text('CXP-000008'), findsOneWidget);
      expect(find.text('Vence el 16 oct'), findsOneWidget);
      expect(find.text('\$222.00'), findsWidgets);
    });

    testWidgets('la CxP de otra orden no se cuela', (tester) async {
      await _pump(
        tester,
        seed: _order(status: PurchaseOrderStatus.received),
        payables: [_payable(purchaseOrderId: 'po-otra')],
      );

      expect(find.text('Cuenta por pagar'), findsNothing);
    });

    testWidgets('una CxP liquidada se lee "Pagada"', (tester) async {
      await _pump(
        tester,
        seed: _order(status: PurchaseOrderStatus.received),
        payables: [_payable(paid: 222)],
      );

      expect(find.text('Pagada'), findsOneWidget);
    });
  });

  group('acción de recibir', () {
    testWidgets('se ofrece mientras falte mercancía', (tester) async {
      await _pump(
        tester,
        seed: _order(status: PurchaseOrderStatus.partiallyReceived),
      );

      expect(find.byKey(const Key('purchaseDetailReceiveButton')),
          findsOneWidget);
    });

    testWidgets('desaparece cuando ya se recibió todo', (tester) async {
      await _pump(tester, seed: _order(status: PurchaseOrderStatus.received));

      expect(
          find.byKey(const Key('purchaseDetailReceiveButton')), findsNothing);
    });

    testWidgets('una orden cancelada no ofrece recibir', (tester) async {
      await _pump(tester, seed: _order(status: PurchaseOrderStatus.cancelled));

      expect(
          find.byKey(const Key('purchaseDetailReceiveButton')), findsNothing);
    });
  });

  testWidgets('pinta la orden viva del provider, no la copia de apertura',
      (tester) async {
    await _pump(
      tester,
      // Se abrió cuando la orden seguía pendiente…
      seed: _order(expectedDeliveryDate: DateTime(2026, 9, 15)),
      // …y para cuando el provider cargó, ya estaba recibida.
      live: _order(
        status: PurchaseOrderStatus.received,
        items: [_item('Coca Cola 600ml', quantity: 12, received: 12)],
        receivedDate: DateTime(2026, 9, 16),
      ),
    );

    expect(find.text('Recibida completa el 16 sep'), findsOneWidget);
    expect(find.text('Llega el 15 sep'), findsNothing);
    expect(find.byKey(const Key('purchaseDetailReceiveButton')), findsNothing);
  });

  group('factura y notas', () {
    testWidgets('se muestran cuando existen', (tester) async {
      await _pump(
        tester,
        seed: _order(
          invoiceReference: 'F-88213',
          notes: 'Entrega por la puerta de atrás',
        ),
      );

      expect(find.text('Factura: F-88213'), findsOneWidget);
      expect(find.text('Entrega por la puerta de atrás'), findsOneWidget);
    });

    testWidgets('sin datos no dejan renglones vacíos', (tester) async {
      await _pump(tester, seed: _order());

      expect(find.textContaining('Factura:'), findsNothing);
    });
  });

  group('editar y cancelar', () {
    testWidgets('una orden pendiente ofrece el menú de acciones',
        (tester) async {
      await _pump(tester, seed: _order());

      expect(find.byKey(const Key('purchaseDetailMenu')), findsOneWidget);
    });

    testWidgets('una orden recibida ya no se puede editar ni cancelar',
        (tester) async {
      await _pump(tester, seed: _order(status: PurchaseOrderStatus.received));

      expect(find.byKey(const Key('purchaseDetailMenu')), findsNothing);
    });

    testWidgets('una orden cancelada tampoco ofrece acciones', (tester) async {
      await _pump(tester, seed: _order(status: PurchaseOrderStatus.cancelled));

      expect(find.byKey(const Key('purchaseDetailMenu')), findsNothing);
    });

    testWidgets('cancelar pide confirmación nombrando el folio',
        (tester) async {
      await _pump(tester, seed: _order());

      await tester.tap(find.byKey(const Key('purchaseDetailMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar orden'));
      await tester.pumpAndSettle();

      expect(find.text('¿Cancelar la orden OC-2026-000012?'), findsOneWidget);
      expect(find.textContaining('seguirá en el historial'), findsOneWidget);
    });

    testWidgets('"Mejor no" deja la orden intacta', (tester) async {
      await _pump(tester, seed: _order());

      await tester.tap(find.byKey(const Key('purchaseDetailMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar orden'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mejor no'));
      await tester.pumpAndSettle();

      verifyNever(() => _lastRepo.cancelPurchaseOrder(
            purchaseOrderId: any(named: 'purchaseOrderId'),
            reason: any(named: 'reason'),
          ));
      expect(find.byKey(const Key('purchaseDetailMenu')), findsOneWidget);
    });

    testWidgets('confirmar manda el motivo capturado', (tester) async {
      await _pump(tester, seed: _order());

      await tester.tap(find.byKey(const Key('purchaseDetailMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar orden'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('cancelOrderReasonField')),
          'El proveedor ya no tiene');
      await tester.tap(find.byKey(const Key('cancelOrderConfirmButton')));
      await tester.pumpAndSettle();

      final captured = verify(() => _lastRepo.cancelPurchaseOrder(
            purchaseOrderId: 'po-1',
            reason: captureAny(named: 'reason'),
          )).captured;
      expect(captured.single, 'El proveedor ya no tiene');
      expect(find.text('Orden OC-2026-000012 cancelada'), findsOneWidget);
      await _drainSnackBar(tester);
    });

    testWidgets('sin motivo no se inventa uno', (tester) async {
      await _pump(tester, seed: _order());

      await tester.tap(find.byKey(const Key('purchaseDetailMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar orden'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelOrderConfirmButton')));
      await tester.pumpAndSettle();

      verify(() => _lastRepo.cancelPurchaseOrder(
            purchaseOrderId: 'po-1',
            reason: null,
          )).called(1);
      await _drainSnackBar(tester);
    });

    testWidgets('si el backend la rechaza, se muestra su motivo tal cual',
        (tester) async {
      await _pump(tester, seed: _order());
      when(() => _lastRepo.cancelPurchaseOrder(
                purchaseOrderId: any(named: 'purchaseOrderId'),
                reason: any(named: 'reason'),
              ))
          .thenThrow(const PurchasesException(
              'Esta orden ya recibió mercancía, así que no se puede cancelar.'));

      await tester.tap(find.byKey(const Key('purchaseDetailMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar orden'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelOrderConfirmButton')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('ya recibió mercancía'),
        findsOneWidget,
      );
      await _drainSnackBar(tester);
    });
  });

  testWidgets('los impuestos en 0 no ocupan renglón', (tester) async {
    await _pump(tester, seed: _order());

    expect(find.text('Impuestos'), findsNothing);
    expect(find.text('Subtotal'), findsNothing);
    expect(find.text('Total'), findsOneWidget);
  });
}
