import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_app/core/router/app_router.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/phone_launcher.dart';
import 'package:nexus_app/features/sales_pos/presentation/cart_provider.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/store_orders_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/store_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/whatsapp_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/store_order_detail_screen.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/store_orders_provider.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/store_orders_screen.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/widgets/new_order_banner.dart';
import 'package:url_launcher/url_launcher.dart';

import 'store_order_fixtures.dart';

class RecordingLauncher {
  final opened = <Uri>[];
  Future<bool> call(Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) {
    opened.add(uri);
    return Future.value(true);
  }
}

late StoreOrdersRepositoryMock repo;
late StreamController<OrderEvent> events;
late RecordingLauncher launcher;

/// App mínima con router: lista, detalle, POS (placeholder) y venta.
Future<GoRouter> pumpApp(WidgetTester tester, {String initial = AppRoutes.storeOrders}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(
      path: AppRoutes.storeOrders,
      builder: (_, state) => StoreOrdersScreen(
        initialTab: state.uri.queryParameters['tab'] == 'historial' ? 1 : 0,
      ),
      routes: [
        GoRoute(
          path: ':folio',
          builder: (_, s) =>
              StoreOrderDetailScreen(folio: s.pathParameters['folio']!),
        ),
      ],
    ),
    GoRoute(path: AppRoutes.sales, builder: (_, __) => const Text('POS')),
    GoRoute(
        path: AppRoutes.saleDetail,
        builder: (_, s) => Text('venta ${s.pathParameters['id']}')),
    GoRoute(
      path: '/shell',
      builder: (_, __) => const Scaffold(
        body: Column(children: [NewOrderBanner(), Text('tab')]),
      ),
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      storeOrdersRepositoryProvider.overrideWithValue(repo),
      orderEventsProvider.overrideWithValue(events.stream),
      inventoryRepositoryProvider.overrideWithValue(InventoryRepositoryMock()),
      urlLauncherProvider.overrideWithValue(launcher.call),
    ],
    child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUp(() {
    // Reloj que avanza un segundo por lectura: así cada cambio en el mock
    // produce un `updatedAt` distinto (concurrencia optimista).
    var tick = 0;
    repo = StoreOrdersRepositoryMock(
      orders: [lauraOrder(), pedroOrder()],
      latency: Duration.zero,
      now: () => fixedNow.add(Duration(seconds: tick++)),
    );
    events = StreamController<OrderEvent>.broadcast();
    launcher = RecordingLauncher();
    addTearDown(events.close);
  });

  group('Lista', () {
    testWidgets('muestra activos con badge, punto de "sin ver" y entrega',
        (tester) async {
      await pumpApp(tester);
      expect(find.text('Pedidos web'), findsOneWidget);
      expect(find.byKey(const Key('newOrdersBadge')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.byKey(const Key('orderRow-P-260916-AB12')), findsOneWidget);
      expect(find.byKey(const Key('orderRow-P-260916-CD34')), findsOneWidget);
      expect(find.byKey(const Key('unseenDot')), findsOneWidget); // sólo Laura
      expect(find.text('Laura Jiménez'), findsOneWidget);
      expect(find.textContaining('Domicilio'), findsOneWidget);
      expect(find.textContaining('Recoger'), findsOneWidget);
      expect(find.text('\$75.50'), findsOneWidget);
    });

    testWidgets('el historial lista los cerrados y el vacío explica',
        (tester) async {
      repo = StoreOrdersRepositoryMock(
        orders: [pedroOrder(status: OrderStatus.delivered)],
        latency: Duration.zero,
        now: () => fixedNow,
      );
      await pumpApp(tester);
      expect(find.text('Nada pendiente'), findsOneWidget);
      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('orderRow-P-260916-CD34')), findsOneWidget);
      expect(find.text('Entregado'), findsOneWidget);
    });

    testWidgets('un pedido que llega por el socket aparece al frente',
        (tester) async {
      await pumpApp(tester);
      events.add(OrderEvent(OrderEventType.newOrder,
          order: lauraOrder(folio: 'P-260916-EF56')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('orderRow-P-260916-EF56')), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // badge
    });

    testWidgets('marca el posible duplicado', (tester) async {
      repo = StoreOrdersRepositoryMock(
        orders: [lauraOrder(folio: 'P-2', possibleDuplicateOf: 'P-1')],
        latency: Duration.zero,
        now: () => fixedNow,
      );
      await pumpApp(tester);
      expect(find.byKey(const Key('duplicateTag')), findsOneWidget);
      expect(find.text('Posible duplicado de P-1'), findsOneWidget);
    });
  });

  group('Detalle', () {
    testWidgets('abrirlo marca visto, muestra cliente, renglones y existencias',
        (tester) async {
      await pumpApp(tester, initial: '/ventas/pedidos/P-260916-AB12');
      expect(find.text('Laura Jiménez'), findsOneWidget);
      expect(find.text('Lo vio Eduardo'), findsOneWidget);
      expect(find.text('A domicilio'), findsOneWidget);
      expect(find.text('Av. Reforma 10, Centro'), findsOneWidget);
      expect(find.text('Coca-Cola 600ml'), findsOneWidget);
      expect(find.byKey(const Key('lineStock-prod-001')), findsOneWidget);
      await tester.dragUntilVisible(find.text('Tocar el timbre'),
          find.byType(ListView), const Offset(0, -200));
      expect(find.text('Tocar el timbre'), findsOneWidget);
      expect(find.byKey(const Key('orderMarkReady')), findsOneWidget);
      expect(find.byKey(const Key('orderChargeSecondary')), findsOneWidget);
      expect(find.byKey(const Key('orderEdit')), findsOneWidget);
      expect(find.byKey(const Key('orderCancel')), findsOneWidget);
      expect(repo.all.firstWhere((o) => o.folio == 'P-260916-AB12').isSeen,
          isTrue);
    });

    testWidgets('"Listo" → la única salida es "Cobrar en caja" (entregar es vender)',
        (tester) async {
      final router = await pumpApp(tester, initial: '/ventas/pedidos/P-260916-AB12');
      await tester.tap(find.byKey(const Key('orderMarkReady')));
      await tester.pumpAndSettle();
      final primary = tester.widget<ElevatedButton>(
          find.byKey(const Key('orderCharge')));
      expect(primary.onPressed, isNotNull);
      expect(find.text('Cobrar en caja'), findsOneWidget);
      expect(find.byKey(const Key('orderNotifyCustomer')), findsOneWidget);
      expect(find.byKey(const Key('orderChargeSecondary')), findsNothing);
      // No existe "entregado sin cobrar": el inventario no se descontaría.
      expect(find.byKey(const Key('orderMarkDelivered')), findsNothing);
      expect(find.textContaining('fuera de caja'), findsNothing);

      await tester.tap(find.byKey(const Key('orderCharge')));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.toString(),
          AppRoutes.sales);
    });

    testWidgets('un pedido entregado (con venta) muestra que está en Historial',
        (tester) async {
      repo = StoreOrdersRepositoryMock(
        orders: [lauraOrder(status: OrderStatus.delivered, saleId: 'sale-9', seenAt: fixedNow)],
        latency: Duration.zero,
        now: () => fixedNow,
      );
      await pumpApp(tester, initial: '/ventas/pedidos/P-260916-AB12');
      expect(find.byKey(const Key('orderInHistoryNote')), findsOneWidget);
      expect(find.byKey(const Key('orderEdit')), findsNothing);
    });

    testWidgets('"Avisar al cliente" abre su chat con el texto de "listo"',
        (tester) async {
      await pumpApp(tester, initial: '/ventas/pedidos/P-260916-AB12');
      await tester.tap(find.byKey(const Key('orderMarkReady')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('orderNotifyCustomer')));
      await tester.pumpAndSettle();

      final uri = launcher.opened.single;
      expect(uri.host, 'wa.me');
      expect(uri.path, '/525518324477');
      expect(uri.queryParameters['text'], contains('P-260916-AB12'));
      expect(uri.queryParameters['text'], contains('va en camino'));
      expect(uri.queryParameters['text'], contains('Hola Laura'));
    });

    testWidgets('el aviso "quedó en Historial" lleva a la pestaña Historial',
        (tester) async {
      await pumpApp(tester, initial: '/ventas/pedidos/P-260916-AB12');
      await tester.tap(find.byKey(const Key('orderCancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelReason-DUPLICATE')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('orderInHistoryNote')), findsOneWidget);

      await tester.tap(find.byKey(const Key('orderGoHistory')));
      await tester.pumpAndSettle();
      expect(find.byKey(const PageStorageKey('historyOrdersList')), findsOneWidget);
      expect(find.byKey(const Key('orderRow-P-260916-AB12')), findsOneWidget);
    });

    testWidgets('Cancelar pide motivo por chips y es reversible',
        (tester) async {
      await pumpApp(tester, initial: '/ventas/pedidos/P-260916-AB12');
      await tester.tap(find.byKey(const Key('orderCancel')));
      await tester.pumpAndSettle();
      expect(find.text('¿Por qué se cancela?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancelReason-OUT_OF_STOCK')));
      await tester.pumpAndSettle();

      expect(find.text('Motivo: Sin existencias'), findsOneWidget);
      expect(find.byKey(const Key('orderReopen')), findsOneWidget);

      await tester.tap(find.byKey(const Key('orderReopen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('orderMarkReady')), findsOneWidget);
    });

    testWidgets('"Escribirle" abre el chat del cliente', (tester) async {
      await pumpApp(tester, initial: '/ventas/pedidos/P-260916-AB12');
      await tester.tap(find.byKey(const Key('orderChatLink')));
      await tester.pumpAndSettle();
      expect(launcher.opened.single.toString(), 'https://wa.me/525518324477');
    });

    testWidgets('sin teléfono no hay botón de chat, sí la explicación',
        (tester) async {
      await pumpApp(tester, initial: '/ventas/pedidos/P-260916-CD34');
      expect(find.byKey(const Key('orderChatButton')), findsNothing);
      expect(find.textContaining('respóndele en el chat'), findsOneWidget);
    });

    testWidgets('Editar: cambia cantidad, quita envío y guarda con historial',
        (tester) async {
      await pumpApp(tester, initial: '/ventas/pedidos/P-260916-AB12');
      await tester.tap(find.byKey(const Key('orderEdit')));
      await tester.pumpAndSettle();
      expect(find.text('Editar P-260916-AB12'), findsOneWidget);

      await tester.tap(find.byKey(const Key('orderEditMinus-prod-001')));
      await tester.pump();
      expect(find.byKey(const Key('orderEditQty-prod-001')), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      await tester.tap(find.text('Recoger'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('orderEditTotal')), findsOneWidget);
      expect(find.text('\$37.00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('orderEditSave')));
      await tester.pumpAndSettle();

      final edited = repo.all.firstWhere((o) => o.folio == 'P-260916-AB12');
      expect(edited.order.draft.lines.single.quantity, 2);
      expect(edited.order.draft.deliveryMethod, DeliveryMethod.pickup);
      expect(edited.revisions, hasLength(1));
      expect(find.textContaining('Editado por Eduardo'), findsOneWidget);
      await tester.dragUntilVisible(find.byKey(const Key('orderRevisions')),
          find.byType(ListView), const Offset(0, -200));
      expect(find.byKey(const Key('orderRevisions')), findsOneWidget);
    });

    testWidgets('"Cobrar en caja" carga el carrito del POS con el pedido',
        (tester) async {
      final router = await pumpApp(tester, initial: '/ventas/pedidos/P-260916-AB12');
      final container = ProviderScope.containerOf(
          tester.element(find.byType(StoreOrderDetailScreen)));
      await tester.tap(find.byKey(const Key('orderChargeSecondary')));
      await tester.pumpAndSettle();

      expect(find.text('POS'), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.uri.toString(),
          AppRoutes.sales);
      final cart = container.read(cartProvider);
      expect(cart.originOrderFolio, 'P-260916-AB12');
      expect(cart.items.single.productId, 'prod-001');
      expect(cart.items.single.quantity, 3);
      expect(cart.items.single.unitPriceMxn, 18.5);
    });

    testWidgets('un pedido cobrado en caja enlaza a la venta y no se reabre',
        (tester) async {
      repo = StoreOrdersRepositoryMock(
        orders: [
          lauraOrder(status: OrderStatus.delivered, saleId: 'sale-9', seenAt: fixedNow),
        ],
        latency: Duration.zero,
        now: () => fixedNow,
      );
      await pumpApp(tester, initial: '/ventas/pedidos/P-260916-AB12');
      expect(find.byKey(const Key('orderSaleLink')), findsOneWidget);
      expect(find.byKey(const Key('orderReopen')), findsNothing);
      await tester.tap(find.byKey(const Key('orderSaleLink')));
      await tester.pumpAndSettle();
      expect(find.text('venta sale-9'), findsOneWidget);
    });

    testWidgets('409: avisa que alguien más lo cambió y recarga',
        (tester) async {
      await pumpApp(tester, initial: '/ventas/pedidos/P-260916-AB12');
      // Otro empleado lo movió por detrás (sin pasar por la pantalla).
      await tester.runAsync(
          () => repo.updateStatus('P-260916-AB12', status: OrderStatus.ready));
      await tester.tap(find.byKey(const Key('orderMarkReady')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Alguien más cambió este pedido'), findsOneWidget);
      // Recargado: ya está Listo, así que ofrece cobrar y avisar.
      expect(find.byKey(const Key('orderMarkReady')), findsNothing);
      expect(find.byKey(const Key('orderNotifyCustomer')), findsOneWidget);
    });
  });

  group('Banner', () {
    testWidgets('un pedido nuevo muestra el banner; "Ver" abre el detalle',
        (tester) async {
      await pumpApp(tester, initial: '/shell');
      expect(find.byKey(const Key('newOrderBanner')), findsNothing);

      events.add(OrderEvent(OrderEventType.newOrder,
          order: lauraOrder(folio: 'P-260916-EF56')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('newOrderBanner')), findsOneWidget);
      expect(find.textContaining('Pedido nuevo · Laura Jiménez'), findsOneWidget);

      await tester.tap(find.byKey(const Key('newOrderBannerOpen')));
      await tester.pumpAndSettle();
      expect(find.byType(StoreOrderDetailScreen), findsOneWidget);
      expect(find.byKey(const Key('newOrderBanner')), findsNothing);
    });

    testWidgets('se descarta con la X o solo a los 12 s', (tester) async {
      await pumpApp(tester, initial: '/shell');
      events.add(OrderEvent(OrderEventType.newOrder,
          order: lauraOrder(folio: 'P-260916-EF56')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('newOrderBannerDismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('newOrderBanner')), findsNothing);

      events.add(OrderEvent(OrderEventType.newOrder,
          order: lauraOrder(folio: 'P-260916-GH78')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('newOrderBanner')), findsOneWidget);
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('newOrderBanner')), findsNothing);
    });
  });
}
