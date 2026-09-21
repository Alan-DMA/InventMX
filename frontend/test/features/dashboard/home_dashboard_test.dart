import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_app/core/router/app_router.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/account/data/operating_warehouse_store.dart';
import 'package:nexus_app/features/account/presentation/account_provider.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/management/data/management_repository.dart';
import 'package:nexus_app/features/management/presentation/management_provider.dart'
    show managementRepositoryProvider;
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/dashboard/data/dashboard_repository.dart';
import 'package:nexus_app/features/dashboard/domain/daily_snapshot.dart';
import 'package:nexus_app/features/dashboard/domain/store_notification.dart';
import 'package:nexus_app/features/dashboard/presentation/dashboard_provider.dart';
import 'package:nexus_app/features/dashboard/presentation/home_dashboard_screen.dart';
import 'package:nexus_app/features/dashboard/presentation/notifications_screen.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart'
    show WarehouseOption, warehousesProvider;
import 'package:nexus_app/features/purchases/presentation/widgets/phone_launcher.dart';
import 'package:nexus_app/features/saas_admin/presentation/saas_provider.dart'
    show clockProvider;
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/store_orders_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/public_catalog.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/store_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/whatsapp_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/store_orders_provider.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// N-08 — Centro de mando y apartado de Avisos
// ---------------------------------------------------------------------------

/// Reloj fijo para que los "hace X min" no dependan de cuándo corra el test.
/// A las 12:00 el saludo cae en "Buenas tardes".
final _now = DateTime(2026, 9, 16, 12, 0);

const _owner = 'eduardo.cristancho@nexus.mx';

class _RecordingLauncher {
  final List<Uri> opened = [];

  Future<bool> call(Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) {
    opened.add(uri);
    return Future.value(true);
  }
}

/// Pedido web real (20 sep 2026): el aviso de pedido ya no sale del mock del
/// dashboard sino de `storeOrdersProvider`. Laura pidió hace 12 min y nadie
/// lo ha abierto — cuenta como aviso sin leer.
StoreOrder _lauraOrder() => StoreOrder(
      order: SavedOrder(
        folio: 'P-260916-AB12',
        slug: 'tiendita-nexus',
        issuedAt: _now.subtract(const Duration(minutes: 12)),
        updatedAt: _now.subtract(const Duration(minutes: 12)),
        draft: const WhatsAppOrderDraft(
          customerName: 'Laura Jiménez',
          customerPhone: '+525518324477',
          deliveryMethod: DeliveryMethod.delivery,
          deliveryAddress: 'Av. Reforma 10',
          lines: [
            CartLine(
              product: PublicCatalogProduct(
                  id: 'prod-001',
                  name: 'Coca-Cola 600ml',
                  sku: 'C1',
                  priceMxn: 18.5),
              quantity: 3,
            ),
          ],
        ),
        totals: WhatsAppOrderBuild(
          waLink: Uri.parse('https://wa.me/525518324477'),
          formattedText: '',
          subtotalMxn: 55.5,
          deliveryFeeMxn: 20,
          totalMxn: 75.5,
          itemCount: 1,
        ),
      ),
    );

ProviderContainer _container({
  _RecordingLauncher? launcher,
  StoreOrdersRepositoryMock? orders,
}) {
  final container = ProviderContainer(
    overrides: [
      // Pedidos web (20 sep 2026): el shell abre el canal en vivo; en tests
      // se sustituye por un stream vacío y el repo mock (sin timers ni red).
      orderEventsProvider.overrideWithValue(const Stream<OrderEvent>.empty()),
      // Personas/roles reales desde la Fase B (Sep 21): mock en tests.
      managementRepositoryProvider.overrideWith(
          (ref) => ManagementRepositoryMock(
                  currentEmail: ref.watch(currentUserNameProvider) ?? 'demo@nexus.mx')),
      storeOrdersRepositoryProvider.overrideWithValue(orders ??
          StoreOrdersRepositoryMock(
              orders: [_lauraOrder()], now: () => _now, latency: Duration.zero)),
      clockProvider.overrideWithValue(() => _now),
      dashboardRepositoryProvider
          .overrideWithValue(DashboardRepositoryMock(now: _now)),
      if (launcher != null)
        urlLauncherProvider.overrideWithValue(launcher.call),
      // Saludo con contexto (Fase 3): identidad + almacén operativo, sin
      // tocar red real (mismo patrón que account_screen_test.dart).
      sessionProvider.overrideWith((ref) => true),
      currentUserNameProvider.overrideWith((ref) => _owner),
      operatingWarehouseStoreProvider
          .overrideWithValue(OperatingWarehouseStoreMemory()),
      // Sin esto, "Ajustar stock" golpearía la red real de Inventario.
      inventoryRepositoryProvider.overrideWithValue(InventoryRepositoryMock()),
      // El almacén operativo del saludo ahora persiste en el backend real.
      authRepositoryProvider
          .overrideWithValue(AuthRepositoryMock(storage: SecureStorage())),
      warehousesProvider.overrideWith((ref) async => const [
            WarehouseOption(
                id: 'wh-001', name: 'Almacén Principal', isDefault: true),
          ]),
      // "Últimas ventas" (recentSalesProvider) pega a salesRepositoryProvider
      // directo — sin esto golpearía la red real desde Sep 2026 (ya no es
      // Mock por defecto).
      salesRepositoryProvider.overrideWith((ref) => SalesRepositoryMock(clock: () => _now)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _app(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark, home: home),
    );

/// La tarjeta "Pedidos web" (20 sep 2026) empuja "Cómo va el día" bajo el
/// pliegue del viewport de prueba; el ListView es perezoso y no lo construye.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(2400, 6000); // 800 × 2000 lógicos
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  group('Resumen del día', () {
    test('la variación contra ayer no se calcula si ayer no hubo ventas', () {
      const sinAyer = DailySnapshot(
        salesTodayMxn: 500,
        salesTodayCount: 3,
        salesYesterdayMxn: 0,
        marginTodayMxn: 0,
        lowStockCount: 0,
        outOfStockCount: 0,
        payablesDueMxn: 0,
        payablesOverdueCount: 0,
        isCashSessionOpen: false,
        cashExpectedMxn: 0,
      );
      expect(sinAyer.salesDeltaPercent, isNull);

      const conAyer = DailySnapshot(
        salesTodayMxn: 1200,
        salesTodayCount: 9,
        salesYesterdayMxn: 1000,
        marginTodayMxn: 300,
        lowStockCount: 2,
        outOfStockCount: 1,
        payablesDueMxn: 0,
        payablesOverdueCount: 0,
        isCashSessionOpen: true,
        cashExpectedMxn: 900,
      );
      expect(conAyer.salesDeltaPercent, 20);
      expect(conAyer.marginTodayPercent, 25);
      expect(conAyer.stockAlertCount, 3);
    });

    testWidgets('muestra ventas, margen, por pagar y caja', (tester) async {
      _tallViewport(tester);
      final container = _container();
      await tester.pumpWidget(_app(container, const HomeDashboardScreen()));
      await _settle(tester);

      expect(find.byKey(const Key('homeSalesTodayAmount')), findsOneWidget);
      expect(find.text('\$3,184.50'), findsOneWidget);
      // 3184.50 contra 2790 de ayer → +14%
      expect(find.text('+14%'), findsOneWidget);
      expect(find.textContaining('42 ventas'), findsOneWidget);

      // 891.70 / 3184.50 ≈ 28%
      expect(find.byKey(const Key('homeMarginToday')), findsOneWidget);
      expect(find.textContaining('\$891.70'), findsOneWidget);
      expect(find.textContaining('28%'), findsOneWidget);

      expect(find.byKey(const Key('homePayables')), findsOneWidget);
      expect(find.text('\$3,240.00'), findsOneWidget);

      expect(find.text('Turno abierto'), findsOneWidget);
    });

    testWidgets('ofrece las tres acciones rápidas del mostrador',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const HomeDashboardScreen()));
      await _settle(tester);

      expect(find.byKey(const Key('homeActionSell')), findsOneWidget);
      expect(find.byKey(const Key('homeActionAddProduct')), findsOneWidget);
      expect(find.byKey(const Key('homeActionAdjustStock')), findsOneWidget);
      // Caja ya tiene su propia tarjeta de estado más abajo — no se duplica.
      expect(find.byKey(const Key('homeActionCash')), findsNothing);
    });

    testWidgets('el saludo trae el nombre y el almacén operativo',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const HomeDashboardScreen()));
      await _settle(tester);

      // 12:00 del reloj fijo → "Buenas tardes"; el nombre lo deriva el mock
      // de Gestión a partir del correo de sesión.
      expect(find.text('Buenas tardes, Eduardo'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            w.key == const Key('homeContextLine') &&
            (w.data ?? '').contains('Almacén Principal')),
        findsOneWidget,
      );
    });

    testWidgets('las alertas de stock se listan en línea, con "Ver todas"',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const HomeDashboardScreen()));
      await _settle(tester);

      // 6 por acabarse + 2 agotados, del mock del Dashboard.
      expect(find.text('8 productos necesitan atención'), findsOneWidget);
      expect(find.byKey(const Key('homeAlertsSeeAll')), findsOneWidget);
      expect(find.text('Ver todas'), findsOneWidget);

      expect(find.byKey(const Key('homeAlertRow-prod-014')), findsOneWidget);
      expect(find.text('Fabuloso 1 L'), findsOneWidget);
      expect(find.text('Agotado'), findsOneWidget);

      expect(find.byKey(const Key('homeAlertRow-prod-001')), findsOneWidget);
      expect(find.text('Quedan 4'), findsOneWidget);
    });

    testWidgets('sin alertas de stock muestra un estado tranquilo',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          // Pedidos web (20 sep 2026): el shell abre el canal en vivo; en tests
          // se sustituye por un stream vacío y el repo mock (sin timers ni red).
          orderEventsProvider.overrideWithValue(const Stream<OrderEvent>.empty()),
      // Personas/roles reales desde la Fase B (Sep 21): mock en tests.
      managementRepositoryProvider.overrideWith(
          (ref) => ManagementRepositoryMock(
                  currentEmail: ref.watch(currentUserNameProvider) ?? 'demo@nexus.mx')),
          // Personas/roles reales desde la Fase B (Sep 21): mock en tests.
          managementRepositoryProvider.overrideWith(
              (ref) => ManagementRepositoryMock(
                  currentEmail: ref.watch(currentUserNameProvider) ?? 'demo@nexus.mx')),
          storeOrdersRepositoryProvider.overrideWithValue(
            StoreOrdersRepositoryMock(latency: Duration.zero)),
          clockProvider.overrideWithValue(() => _now),
          dashboardRepositoryProvider
              .overrideWithValue(_NoAlertsMock(now: _now)),
          sessionProvider.overrideWith((ref) => true),
          currentUserNameProvider.overrideWith((ref) => _owner),
          operatingWarehouseStoreProvider
              .overrideWithValue(OperatingWarehouseStoreMemory()),
          inventoryRepositoryProvider
              .overrideWithValue(InventoryRepositoryMock()),
          salesRepositoryProvider
              .overrideWith((ref) => SalesRepositoryMock(clock: () => _now)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container, const HomeDashboardScreen()));
      await _settle(tester);

      expect(find.text('Todo en orden — sin productos por acabarse'),
          findsOneWidget);
      expect(find.byKey(const Key('homeAlertsSeeAll')), findsNothing);
    });

    testWidgets('las últimas ventas se muestran condensadas con "Ver todo"',
        (tester) async {
      _tallViewport(tester);
      final container = _container();
      await tester.pumpWidget(_app(container, const HomeDashboardScreen()));
      await _settle(tester);

      expect(find.text('Últimas ventas'), findsOneWidget);
      expect(find.byKey(const Key('homeSalesSeeAll')), findsOneWidget);
      expect(find.text('Ver todo'), findsOneWidget);
    });

    testWidgets('"Ajustar stock" abre el buscador y salta al modal de ajuste',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const HomeDashboardScreen()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('homeActionAdjustStock')));
      await _settle(tester);

      expect(find.byKey(const Key('quickAdjustSearchField')), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('quickAdjustSearchField')), 'Pepsi');
      await _settle(tester);

      expect(find.textContaining('Pepsi 2L'), findsOneWidget);

      await tester.tap(find.textContaining('Pepsi 2L'));
      await _settle(tester);

      // El buscador se cierra y abre el modal de ajuste ya existente.
      expect(find.byKey(const Key('quickAdjustSearchField')), findsNothing);
      expect(find.text('Ajustar stock'), findsWidgets);
    });

    testWidgets('la campana lleva el contador de avisos sin leer',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const HomeDashboardScreen()));
      await _settle(tester);

      expect(find.byKey(const Key('homeNotificationsBadge')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('Avisos', () {
    testWidgets('lista los avisos con su antigüedad', (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const NotificationsScreen()));
      await _settle(tester);

      expect(find.text('Pedido nuevo de Laura Jiménez'), findsOneWidget);
      expect(find.text('Se está agotando Coca-Cola 600 ml'), findsOneWidget);
      expect(find.text('hace 12 min'), findsOneWidget);
      expect(find.text('ayer'), findsOneWidget);
    });

    testWidgets('el aviso de pedido abre el pedido en la app (no el chat)',
        (tester) async {
      final launcher = _RecordingLauncher();
      final container = _container(launcher: launcher);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const NotificationsScreen()),
        GoRoute(
          path: AppRoutes.storeOrderDetail,
          builder: (_, state) =>
              Text('detalle ${state.pathParameters['folio']}'),
        ),
      ]);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ));
      await _settle(tester);

      expect(find.text('Ver el pedido'), findsOneWidget);
      await tester
          .tap(find.byKey(const Key('notification-order-P-260916-AB12')));
      await _settle(tester);

      expect(find.text('detalle P-260916-AB12'), findsOneWidget);
      expect(launcher.opened, isEmpty);
    });

    testWidgets('"Marcar leídos" deja sólo el pedido pendiente sin leer',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const NotificationsScreen()));
      await _settle(tester);

      expect(container.read(unreadNotificationsProvider), 3);
      await tester.tap(find.byKey(const Key('notificationsMarkAll')));
      await _settle(tester);

      // El pedido web no es un aviso que se "lee": es trabajo pendiente y se
      // marca al abrirlo. Los demás sí quedan leídos.
      expect(container.read(unreadNotificationsProvider), 1);
    });

    testWidgets('abrir el pedido lo marca visto y el aviso queda leído',
        (tester) async {
      final orders = StoreOrdersRepositoryMock(
          orders: [_lauraOrder()], now: () => _now, latency: Duration.zero);
      final container = _container(orders: orders);
      await tester.pumpWidget(_app(container, const NotificationsScreen()));
      await _settle(tester);
      expect(container.read(unreadNotificationsProvider), 3);

      // Lo que hace la pantalla de detalle al abrirse. `runAsync`: el mock
      // resuelve con timers reales que el reloj falso del test no avanza.
      await tester.runAsync(() async {
        await container.read(storeOrderDetailProvider('P-260916-AB12').future);
        await container.read(storeOrdersProvider.notifier).refresh();
      });
      await _settle(tester);

      expect(container.read(unreadNotificationsProvider), 2);
    });

    testWidgets('sin avisos explica para qué sirve el apartado',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          // Pedidos web (20 sep 2026): el shell abre el canal en vivo; en tests
          // se sustituye por un stream vacío y el repo mock (sin timers ni red).
          orderEventsProvider.overrideWithValue(const Stream<OrderEvent>.empty()),
      // Personas/roles reales desde la Fase B (Sep 21): mock en tests.
      managementRepositoryProvider.overrideWith(
          (ref) => ManagementRepositoryMock(
                  currentEmail: ref.watch(currentUserNameProvider) ?? 'demo@nexus.mx')),
          // Personas/roles reales desde la Fase B (Sep 21): mock en tests.
          managementRepositoryProvider.overrideWith(
              (ref) => ManagementRepositoryMock(
                  currentEmail: ref.watch(currentUserNameProvider) ?? 'demo@nexus.mx')),
          storeOrdersRepositoryProvider.overrideWithValue(
            StoreOrdersRepositoryMock(latency: Duration.zero)),
          clockProvider.overrideWithValue(() => _now),
          dashboardRepositoryProvider.overrideWithValue(_EmptyMock(now: _now)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container, const NotificationsScreen()));
      await _settle(tester);

      expect(find.text('Nada que revisar'), findsOneWidget);
    });
  });

  group('DailySnapshot — parseo robusto de tipos', () {
    test('DailySnapshot.fromJson soporta strings de Decimal ("0.00")', () {
      final json = {
        'period_info': {
          'period': 'TODAY',
          'start_date': '2026-09-21',
          'end_date': '2026-09-21',
        },
        'sales_metrics': {
          'total_revenue_mxn': '0.00',
          'total_orders': '0',
          'average_ticket_mxn': '0.00',
          'revenue_change_percent': null,
        },
        'profitability': {
          'gross_profit_mxn': '0.00',
          'gross_margin_percent': '0.00',
          'margin_change_percent': null,
        },
        'inventory_metrics': {
          'total_products': 0,
          'products_with_stock': 0,
          'low_stock_alerts': '0',
          'inventory_value_mxn': '0.00',
          'turnover_rate': null,
        },
        'top_products': [],
        'critical_stock_alerts': [
          {
            'product_id': 'prod-001',
            'product_name': 'Coca Cola',
            'sku': 'CC-600',
            'current_stock': '0.00',
            'min_stock': '5.00',
            'is_out_of_stock': true,
          }
        ],
        'pending_purchases': [
          {
            'id': 'po-001',
            'folio': 'OC-0001',
            'supplier_name': 'Distribuidora',
            'total_mxn': '1500.50',
            'days_pending': '2',
            'is_overdue': false,
          }
        ],
      };

      final snapshot = DailySnapshot.fromJson(json);

      expect(snapshot.salesTodayMxn, equals(0.0));
      expect(snapshot.salesTodayCount, equals(0));
      expect(snapshot.marginTodayMxn, equals(0.0));
      expect(snapshot.lowStockAlerts.length, equals(1));
      expect(snapshot.lowStockAlerts.first.availableStock, equals(0));
      expect(snapshot.lowStockAlerts.first.minStock, equals(5));
      expect(snapshot.pendingPurchasesAlerts.length, equals(1));
      expect(snapshot.pendingPurchasesAlerts.first.totalMxn, equals(1500.50));
      expect(snapshot.pendingPurchasesAlerts.first.daysPending, equals(2));
      expect(snapshot.payablesDueMxn, equals(1500.50));
    });
  });
}

/// Buzón vacío — para el estado sin avisos.
class _EmptyMock extends DashboardRepositoryMock {
  _EmptyMock({super.now});

  @override
  Future<List<StoreNotification>> listNotifications() async => const [];
}

/// Snapshot sin alertas de stock — para el estado "Todo en orden".
class _NoAlertsMock extends DashboardRepositoryMock {
  _NoAlertsMock({super.now});

  @override
  Future<DailySnapshot> getTodaySnapshot() async {
    final base = await super.getTodaySnapshot();
    return DailySnapshot(
      salesTodayMxn: base.salesTodayMxn,
      salesTodayCount: base.salesTodayCount,
      salesYesterdayMxn: base.salesYesterdayMxn,
      marginTodayMxn: base.marginTodayMxn,
      lowStockCount: 0,
      outOfStockCount: 0,
      lowStockAlerts: const [],
      payablesDueMxn: base.payablesDueMxn,
      payablesOverdueCount: base.payablesOverdueCount,
      isCashSessionOpen: base.isCashSessionOpen,
      cashExpectedMxn: base.cashExpectedMxn,
    );
  }
}
