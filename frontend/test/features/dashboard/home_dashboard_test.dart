import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/account/data/operating_warehouse_store.dart';
import 'package:nexus_app/features/account/presentation/account_provider.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
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

ProviderContainer _container({_RecordingLauncher? launcher}) {
  final container = ProviderContainer(
    overrides: [
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
          clockProvider.overrideWithValue(() => _now),
          dashboardRepositoryProvider
              .overrideWithValue(_NoAlertsMock(now: _now)),
          sessionProvider.overrideWith((ref) => true),
          currentUserNameProvider.overrideWith((ref) => _owner),
          operatingWarehouseStoreProvider
              .overrideWithValue(OperatingWarehouseStoreMemory()),
          inventoryRepositoryProvider
              .overrideWithValue(InventoryRepositoryMock()),
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

    testWidgets('el aviso de pedido abre el chat de quien lo hizo',
        (tester) async {
      final launcher = _RecordingLauncher();
      final container = _container(launcher: launcher);
      await tester.pumpWidget(_app(container, const NotificationsScreen()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('notification-ntf-001')));
      await _settle(tester);

      expect(launcher.opened.single.toString(),
          'https://wa.me/525518324477');
      // Y queda leído: el contador baja de 3 a 2.
      expect(container.read(unreadNotificationsProvider), 2);
    });

    testWidgets('"Marcar leídos" vacía el contador', (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const NotificationsScreen()));
      await _settle(tester);

      expect(container.read(unreadNotificationsProvider), 3);
      await tester.tap(find.byKey(const Key('notificationsMarkAll')));
      await _settle(tester);

      expect(container.read(unreadNotificationsProvider), 0);
      expect(find.byKey(const Key('notificationsMarkAll')), findsNothing);
    });

    testWidgets('sin avisos explica para qué sirve el apartado',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
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
