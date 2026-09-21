import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/purchases/data/purchases_repository.dart';
import 'package:nexus_app/features/purchases/domain/account_payable.dart';
import 'package:nexus_app/features/purchases/domain/purchase_order.dart';
import 'package:nexus_app/features/purchases/presentation/purchases_provider.dart';

// ---------------------------------------------------------------------------
// Se usa el `PurchasesRepositoryMock` real (no mocktail) — mismo criterio que
// `cash_session_provider_test.dart`: los notifiers leen del mock semilla que
// modela el hub de Compras/Proveedores/CxP tal como se ve en el Figma
// referencial de la Tarea 11.2. `purchasesRepositoryProvider` ya apunta al
// backend real (retome de Compras) — se sobreescribe a propósito.
// ---------------------------------------------------------------------------

Future<ProviderContainer> _makeContainer() async {
  final container = ProviderContainer(
    overrides: [
      purchasesRepositoryProvider.overrideWithValue(PurchasesRepositoryMock()),
    ],
  );
  addTearDown(container.dispose);
  // Los notifiers disparan su carga inicial en un microtask (build());
  // `retry()` fuerza una carga awaited y determinista para el test.
  await container.read(purchaseOrdersProvider.notifier).retry();
  await container.read(suppliersProvider.notifier).retry();
  await container.read(accountsPayableProvider.notifier).retry();
  return container;
}

void main() {
  group('PurchaseOrdersNotifier — chips Todas/Pendientes/Recibidas', () {
    test('la semilla del mock carga 5 órdenes (SENT/PARTIAL_RECEIVED/RECEIVED)', () async {
      final container = await _makeContainer();
      final state = container.read(purchaseOrdersProvider);

      expect(state.allCount, 5);
      expect(state.pendingCount, 2); // po-001 (SENT) + po-003 (PARTIAL_RECEIVED)
      expect(state.receivedCount, 3); // po-002 + po-004 + po-005
    });

    test('cambiar de chip filtra localmente sin perder el conteo total', () async {
      final container = await _makeContainer();
      final notifier = container.read(purchaseOrdersProvider.notifier);

      notifier.setChipFilter(PurchaseChipFilter.received);
      final state = container.read(purchaseOrdersProvider);

      expect(state.chipFilter, PurchaseChipFilter.received);
      expect(state.visibleOrders, hasLength(3));
      expect(state.visibleOrders.every((o) => o.status == PurchaseOrderStatus.received), isTrue);
      // El conteo total no cambia por el chip activo.
      expect(state.allCount, 5);
    });

    test('la búsqueda por folio filtra la lista', () async {
      final container = await _makeContainer();
      final notifier = container.read(purchaseOrdersProvider.notifier);

      notifier.setSearch('000013');
      await Future<void>.delayed(const Duration(milliseconds: 900));

      final state = container.read(purchaseOrdersProvider);
      expect(state.orders, hasLength(1));
      expect(state.orders.first.folio, 'OC-2026-000013');
    });
  });

  group('PurchaseOrdersNotifier — creación de órdenes', () {
    test('createOrder inserta la nueva orden al inicio de la lista', () async {
      final container = await _makeContainer();
      final notifier = container.read(purchaseOrdersProvider.notifier);
      final before = container.read(purchaseOrdersProvider).allCount;

      final created = await notifier.createOrder(
        supplierId: 'sup-001',
        items: const [
          PurchaseOrderItem(productId: 'new-1', productName: 'Producto nuevo', quantity: 5, unitCostMxn: 20),
        ],
      );

      final state = container.read(purchaseOrdersProvider);
      expect(state.allCount, before + 1);
      expect(state.orders.first.id, created.id);
      expect(state.orders.first.status, PurchaseOrderStatus.confirmed);
      expect(created.totalMxn, 100);
    });
  });

  group('PurchaseOrdersNotifier — recepción de mercancía', () {
    test('recibir todas las líneas cambia el estado a RECEIVED y genera CxP', () async {
      final container = await _makeContainer();
      final notifier = container.read(purchaseOrdersProvider.notifier);

      final order = container
          .read(purchaseOrdersProvider)
          .orders
          .firstWhere((o) => o.id == 'po-001'); // SENT, a crédito, sin CxP previa

      final updatedItems = order.items.map((i) => i.copyWith(quantityReceived: i.quantity)).toList();
      final updated = await notifier.receiveOrder(purchaseOrderId: order.id, updatedItems: updatedItems);

      expect(updated.status, PurchaseOrderStatus.received);
      expect(updated.receivedDate, isNotNull);

      // La recepción de una orden a crédito genera una cuenta por pagar
      // nueva — `receiveOrder` invalida `accountsPayableProvider`, cuya
      // recarga es un microtask async; `retry()` la espera de forma
      // determinista en vez de competir con ese microtask.
      await container.read(accountsPayableProvider.notifier).retry();
      final payables = container.read(accountsPayableProvider);
      expect(payables.items.any((p) => p.purchaseOrderId == order.id), isTrue);
    });

    test('recibir solo algunas líneas cambia el estado a PARTIAL_RECEIVED', () async {
      final container = await _makeContainer();
      final notifier = container.read(purchaseOrdersProvider.notifier);

      final order = container.read(purchaseOrdersProvider).orders.firstWhere((o) => o.id == 'po-001');
      final firstItem = order.items.first;
      final updatedItems = [
        firstItem.copyWith(quantityReceived: 1),
        ...order.items.skip(1),
      ];

      final updated = await notifier.receiveOrder(purchaseOrderId: order.id, updatedItems: updatedItems);
      expect(updated.status, PurchaseOrderStatus.partiallyReceived);
    });
  });

  group('SuppliersNotifier', () {
    test('la semilla carga 3 proveedores', () async {
      final container = await _makeContainer();
      expect(container.read(suppliersProvider).suppliers, hasLength(3));
    });

    test('la búsqueda filtra por nombre', () async {
      final container = await _makeContainer();
      container.read(suppliersProvider.notifier).setSearch('sabritas');
      await Future<void>.delayed(const Duration(milliseconds: 900));

      final state = container.read(suppliersProvider);
      expect(state.suppliers, hasLength(1));
      expect(state.suppliers.first.name, contains('Sabritas'));
    });
  });

  group('AccountsPayableNotifier — abonos', () {
    test('la semilla carga 3 cuentas por pagar con el resumen agregado', () async {
      final container = await _makeContainer();
      final state = container.read(accountsPayableProvider);

      expect(state.items, hasLength(3));
      expect(state.summary, isNotNull);
      expect(state.summary!.overdueCount, 1); // ap-po-004
    });

    test('un abono parcial reduce el saldo sin sacar la cuenta de la lista', () async {
      final container = await _makeContainer();
      final notifier = container.read(accountsPayableProvider.notifier);
      final target = container.read(accountsPayableProvider).items.firstWhere((p) => p.id == 'ap-po-005');

      await notifier.registerPayment(
        accountPayableId: target.id,
        amountPaidMxn: 500,
        paymentMethod: SupplierPaymentMethod.spei,
      );

      final updated = container.read(accountsPayableProvider).items.firstWhere((p) => p.id == 'ap-po-005');
      expect(updated.paidAmountMxn, 500);
      expect(updated.balanceMxn, target.originalAmountMxn - 500);
    });

    test('un abono que liquida el saldo total saca la cuenta de la lista', () async {
      final container = await _makeContainer();
      final notifier = container.read(accountsPayableProvider.notifier);
      final target = container.read(accountsPayableProvider).items.firstWhere((p) => p.id == 'ap-po-005');

      await notifier.registerPayment(
        accountPayableId: target.id,
        amountPaidMxn: target.balanceMxn,
        paymentMethod: SupplierPaymentMethod.cashMxn,
      );

      final state = container.read(accountsPayableProvider);
      expect(state.items.any((p) => p.id == 'ap-po-005'), isFalse);
    });

    test('un abono que excede el saldo pendiente lanza y no modifica el estado', () async {
      final container = await _makeContainer();
      final notifier = container.read(accountsPayableProvider.notifier);
      final target = container.read(accountsPayableProvider).items.first;

      await expectLater(
        notifier.registerPayment(
          accountPayableId: target.id,
          amountPaidMxn: target.balanceMxn + 500,
          paymentMethod: SupplierPaymentMethod.spei,
        ),
        throwsException,
      );

      final unchanged = container.read(accountsPayableProvider).items.firstWhere((p) => p.id == target.id);
      expect(unchanged.paidAmountMxn, target.paidAmountMxn);
    });
  });
}
