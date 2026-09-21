import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/order_events_channel.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/store_orders_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/store_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/whatsapp_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/store_orders_provider.dart';

import 'store_order_fixtures.dart';

/// `storeOrdersProvider` — la lista viva del tendero: eventos del socket,
/// badge, acciones y concurrencia (plan del 20 sep 2026).
void main() {
  late StoreOrdersRepositoryMock repo;
  late StreamController<OrderEvent> events;
  late ProviderContainer container;

  setUp(() {
    repo = StoreOrdersRepositoryMock(
      orders: [lauraOrder(), pedroOrder()],
      latency: Duration.zero,
      now: () => fixedNow,
    );
    events = StreamController<OrderEvent>.broadcast();
    container = ProviderContainer(overrides: [
      storeOrdersRepositoryProvider.overrideWithValue(repo),
      orderEventsProvider.overrideWithValue(events.stream),
    ]);
    addTearDown(container.dispose);
    addTearDown(events.close);
  });

  Future<StoreOrderList> load() => container.read(storeOrdersProvider.future);

  test('carga los activos con el badge del servidor', () async {
    final list = await load();
    expect(list.items.map((o) => o.folio), ['P-260916-AB12', 'P-260916-CD34']);
    expect(list.newCount, 1); // Laura: nueva y sin ver
    expect(list.activeCount, 2);
    expect(container.read(newOrdersCountProvider), 1);
  });

  test('order.new entra al frente, sube el badge y dispara el banner', () async {
    await load();
    final nuevo = lauraOrder(folio: 'P-260916-EF56');
    events.add(OrderEvent(OrderEventType.newOrder, order: nuevo));
    await Future<void>.delayed(Duration.zero);

    final list = container.read(storeOrdersProvider).requireValue;
    expect(list.items.first.folio, 'P-260916-EF56');
    expect(list.newCount, 2);
    expect(list.activeCount, 3);
    expect(container.read(incomingOrderProvider)?.folio, 'P-260916-EF56');
  });

  test('order.updated reemplaza; si el pedido se cerró sale de activos', () async {
    await load();
    final visto = lauraOrder(seenAt: fixedNow);
    events.add(OrderEvent(OrderEventType.updated, order: visto));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(storeOrdersProvider).requireValue.newCount, 0);
    expect(container.read(incomingOrderProvider), isNull); // no es "nuevo"

    final entregado = lauraOrder(status: OrderStatus.delivered, seenAt: fixedNow);
    events.add(OrderEvent(OrderEventType.updated, order: entregado));
    await Future<void>.delayed(Duration.zero);
    final list = container.read(storeOrdersProvider).requireValue;
    expect(list.items.map((o) => o.folio), ['P-260916-CD34']);
    expect(list.activeCount, 1);
  });

  test('reconnected vuelve a pedir al servidor lo que cambió', () async {
    await load();
    // Mientras el socket estaba caído entró un pedido directo al "servidor"
    // (con `updated_at` posterior a la última sincronización del provider).
    final fresh = lauraOrder(folio: 'P-260916-ZZ99');
    repo.receive(fresh.copyWith(
        order: fresh.order.copyWith(
            updatedAt: DateTime.now().add(const Duration(seconds: 1)))));
    events.add(const OrderEvent.reconnected());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final list = container.read(storeOrdersProvider).requireValue;
    expect(list.items.any((o) => o.folio == 'P-260916-ZZ99'), isTrue);
  });

  test('setStatus aplica el cambio y el pedido cerrado sale de la lista', () async {
    await load();
    final notifier = container.read(storeOrdersProvider.notifier);
    // Entregar es vender: sin venta ligada se rechaza.
    await expectLater(
      notifier.setStatus('P-260916-CD34', OrderStatus.delivered),
      throwsA(isA<OrderActionRejected>()),
    );
    final updated = await notifier.setStatus('P-260916-CD34', OrderStatus.delivered,
        saleId: 'sale-1');
    expect(updated.status, OrderStatus.delivered);
    final list = container.read(storeOrdersProvider).requireValue;
    expect(list.items.map((o) => o.folio), ['P-260916-AB12']);
  });

  test('cancelar sin motivo se rechaza; con motivo queda registrado', () async {
    await load();
    final notifier = container.read(storeOrdersProvider.notifier);
    await expectLater(
      notifier.setStatus('P-260916-AB12', OrderStatus.cancelled),
      throwsA(isA<OrderActionRejected>()),
    );
    final cancelled = await notifier.setStatus(
      'P-260916-AB12',
      OrderStatus.cancelled,
      cancelReason: CancelReason.customerCancelled,
    );
    expect(cancelled.order.cancelReason, CancelReason.customerCancelled);
    expect(cancelled.status, OrderStatus.cancelled);
  });

  test('409: versión vieja → OrderConflict y la lista se recarga', () async {
    await load();
    final notifier = container.read(storeOrdersProvider.notifier);
    // Alguien más lo movió (updatedAt cambió en el "servidor").
    await notifier.setStatus('P-260916-AB12', OrderStatus.ready);
    final stale = lauraOrder().order.updatedAt;

    await expectLater(
      notifier.setStatus('P-260916-AB12', OrderStatus.cancelled,
          cancelReason: CancelReason.other, expectedUpdatedAt: stale),
      throwsA(isA<OrderConflict>()),
    );
    expect(
      container.read(storeOrdersProvider).requireValue.items
          .firstWhere((o) => o.folio == 'P-260916-AB12')
          .status,
      OrderStatus.ready,
    );
  });

  test('edit conserva la versión anterior y recalcula el total', () async {
    await load();
    final edited = await container.read(storeOrdersProvider.notifier).edit(
          'P-260916-AB12',
          const StoreOrderEdit(
            lines: [CartLine(product: cocaCola, quantity: 1)],
            deliveryMethod: DeliveryMethod.pickup,
          ),
        );
    expect(edited.order.totals.totalMxn, 18.5);
    expect(edited.order.draft.deliveryMethod, DeliveryMethod.pickup);
    expect(edited.revisions.single.totalMxn, 75.5);
    expect(edited.revisions.single.lines.single.quantity, 3);
    expect(edited.order.storeEditedAt, isNotNull);
  });

  test('linkSale deja el pedido entregado con su venta y nunca lanza', () async {
    await load();
    final notifier = container.read(storeOrdersProvider.notifier);
    await notifier.linkSale('P-260916-AB12', 'sale-77');
    final all = await repo.list(scope: 'all');
    final laura = all.items.firstWhere((o) => o.folio == 'P-260916-AB12');
    expect(laura.status, OrderStatus.delivered);
    expect(laura.saleId, 'sale-77');

    // Un folio inexistente no revienta la venta que ya se hizo.
    await notifier.linkSale('P-000000-XXXX', 'sale-78');
  });

  group('OrderEventsChannel', () {
    final channel = OrderEventsChannel(
      apiBaseUrl: 'http://192.168.50.56:8000',
      readToken: () async => 'tok',
    );

    test('arma la URL ws con el token en query', () {
      final uri = channel.socketUri('abc');
      expect(uri.toString(), 'ws://192.168.50.56:8000/api/v1/ws/orders?token=abc');
      final secure = OrderEventsChannel(
          apiBaseUrl: 'https://api.nexus.mx', readToken: () async => 't');
      expect(secure.socketUri('t').scheme, 'wss');
    });

    test('parsea order.new / order.updated / ping y descarta lo raro', () {
      const json =
          '{"type":"order.new","order":{"folio":"P-1","store_slug":"s","created_at":"2026-09-16T12:00:00Z",'
          '"customer_name":"Ana","delivery_method":"PICKUP","payment_method":"CASH","items":[],'
          '"subtotal_mxn":"0","delivery_fee_mxn":"0","total_mxn":"0","item_count":0,'
          '"wa_link":"https://wa.me/","formatted_text":"","status":"NEW"}}';
      final event = OrderEventsChannel.parse(json)!;
      expect(event.type, OrderEventType.newOrder);
      expect(event.order!.folio, 'P-1');
      expect(OrderEventsChannel.parse('{"type":"ping"}')!.type, OrderEventType.ping);
      expect(OrderEventsChannel.parse('{"type":"order.updated"}'), isNull);
      expect(OrderEventsChannel.parse('no es json'), isNull);
    });

    test('la espera entre reintentos crece y se acota', () {
      expect(channel.backoff(1), const Duration(seconds: 1));
      expect(channel.backoff(3), const Duration(seconds: 4));
      expect(channel.backoff(10), const Duration(seconds: 30));
    });
  });
}
