import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/router/app_router.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/account/data/operating_warehouse_store.dart';
import 'package:nexus_app/features/account/presentation/account_provider.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/dashboard/data/dashboard_repository.dart';
import 'package:nexus_app/features/dashboard/domain/quick_action_item.dart';
import 'package:nexus_app/features/dashboard/domain/store_notification.dart';
import 'package:nexus_app/features/dashboard/presentation/dashboard_provider.dart';
import 'package:nexus_app/features/dashboard/presentation/quick_actions_preference.dart';
import 'package:nexus_app/features/dashboard/presentation/widgets/app_drawer.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart'
    show warehousesProvider, WarehouseOption;
import 'package:nexus_app/features/management/data/management_repository.dart';
import 'package:nexus_app/features/management/domain/app_permission.dart';
import 'package:nexus_app/features/management/presentation/management_provider.dart'
    hide warehousesProvider;
import 'package:nexus_app/features/onboarding/presentation/onboarding_provider.dart';
import 'package:nexus_app/features/purchases/data/purchases_repository.dart';
import 'package:nexus_app/features/purchases/presentation/purchases_provider.dart';
import 'package:nexus_app/features/saas_admin/data/saas_repository.dart';
import 'package:nexus_app/features/saas_admin/presentation/saas_provider.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/store_order.dart' show OrderEvent;
import 'package:nexus_app/features/whatsapp_catalog/data/store_orders_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/store_orders_provider.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/widgets/new_order_banner.dart';

// ---------------------------------------------------------------------------
// Permisos por rol — Fase A (Sep 22, 2026): pestañas, menú ☰, Inicio, avisos
// y router por rol. Los cuatro roles salen de la semilla del mock de Gestión,
// que replica exactamente `0002_seed_rbac_permissions.py`.
// ---------------------------------------------------------------------------

final _now = DateTime(2026, 9, 22, 12, 0);

const _owner = 'eduardo.cristancho@nexus.mx';
const _manager = 'maria.hernandez@nexus.mx';
const _cashier = 'jose.ramirez@nexus.mx';
const _warehouse = 'carlos.mendoza@nexus.mx';

ProviderContainer _container({String email = _owner}) {
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith((ref) => true),
      onboardingCompleteProvider.overrideWith((ref) => true),
      currentUserNameProvider.overrideWith((ref) => email),
      managementRepositoryProvider.overrideWith(
          (ref) => ManagementRepositoryMock(currentEmail: email)),
      orderEventsProvider.overrideWithValue(const Stream<OrderEvent>.empty()),
      storeOrdersRepositoryProvider
          .overrideWithValue(StoreOrdersRepositoryMock(latency: Duration.zero)),
      clockProvider.overrideWithValue(() => _now),
      dashboardRepositoryProvider
          .overrideWithValue(DashboardRepositoryMock(now: _now)),
      operatingWarehouseStoreProvider
          .overrideWithValue(OperatingWarehouseStoreMemory()),
      inventoryRepositoryProvider.overrideWithValue(InventoryRepositoryMock()),
      authRepositoryProvider
          .overrideWithValue(AuthRepositoryMock(storage: SecureStorage())),
      warehousesProvider.overrideWith((ref) async => const [
            WarehouseOption(
                id: 'wh-001', name: 'Almacén Principal', isDefault: true),
          ]),
      salesRepositoryProvider
          .overrideWith((ref) => SalesRepositoryMock(clock: () => _now)),
      purchasesRepositoryProvider.overrideWithValue(PurchasesRepositoryMock()),
      saasRepositoryProvider.overrideWithValue(
          SaasRepositoryMock(currentEmail: email, latency: Duration.zero)),
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

Widget _routerApp(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (_, ref, __) => MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: ref.watch(appRouterProvider),
        ),
      ),
    );

/// El Inicio es un ListView perezoso: con el viewport de prueba por defecto
/// "Cómo va el día" queda bajo el pliegue y no se construye.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(2400, 6000); // 800 × 2000 lógicos
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Los mocks responden con retardo: el reloj se avanza a mano.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// Resuelve quién soy (y con ello los permisos) sin montar UI.
Future<void> _loadMe(ProviderContainer container) async {
  container.listen(currentMemberProvider, (_, __) {});
  await container.read(currentMemberProvider.future);
}

void main() {
  group('permisos efectivos (CA-01)', () {
    test('cada rol recibe exactamente los permisos de la semilla', () async {
      final owner = _container();
      await _loadMe(owner);
      expect(owner.read(myPermissionsProvider), Permissions.all);
      expect(owner.read(myPermissionsProvider).length, 21);
      expect(owner.read(isOwnerProvider), isTrue);

      final cashier = _container(email: _cashier);
      await _loadMe(cashier);
      expect(cashier.read(myPermissionsProvider), {
        Permissions.inventoryView,
        Permissions.salesView,
        Permissions.salesCheckout,
        Permissions.cashView,
        Permissions.cashOpenSession,
        Permissions.cashCloseSession,
        Permissions.cashManualMovement,
      });
      expect(cashier.read(isOwnerProvider), isFalse);
      expect(cashier.read(canSeeReportsProvider), isFalse);

      final manager = _container(email: _manager);
      await _loadMe(manager);
      expect(manager.read(canManageMembersProvider), isTrue);
      expect(manager.read(canSeeSubscriptionProvider), isFalse);
      expect(manager.read(myPermissionsProvider),
          isNot(contains(Permissions.settingsBilling)));
    });

    test('sin sesión resuelta no hay permisos: fail-closed', () {
      final container = _container(email: _cashier);
      expect(container.read(permissionsKnownProvider), isFalse);
      expect(container.read(myPermissionsProvider), isEmpty);
      expect(container.read(visibleTabsProvider),
          [ShellTab.home, ShellTab.inventory]);
    });
  });

  group('pestañas del shell (CA-02)', () {
    test('Dueño/Encargado 5 · Cajero 4 sin Compras · Almacenista 3', () async {
      final owner = _container();
      await _loadMe(owner);
      expect(owner.read(visibleTabsProvider), ShellTab.values);

      final cashier = _container(email: _cashier);
      await _loadMe(cashier);
      expect(cashier.read(visibleTabsProvider),
          [ShellTab.home, ShellTab.inventory, ShellTab.sales, ShellTab.cash]);

      final warehouse = _container(email: _warehouse);
      await _loadMe(warehouse);
      expect(warehouse.read(visibleTabsProvider),
          [ShellTab.home, ShellTab.inventory, ShellTab.purchases]);
    });

    testWidgets('la barra pinta sólo las pestañas del rol y navega a su rama',
        (tester) async {
      final container = _container(email: _warehouse);
      await tester.pumpWidget(_routerApp(container));
      await _settle(tester);

      expect(find.byKey(const Key('shellTab-home')), findsOneWidget);
      expect(find.byKey(const Key('shellTab-inventory')), findsOneWidget);
      expect(find.byKey(const Key('shellTab-purchases')), findsOneWidget);
      expect(find.byKey(const Key('shellTab-sales')), findsNothing);
      expect(find.byKey(const Key('shellTab-cash')), findsNothing);
      // Sin sales.view no se abre el canal de pedidos web.
      expect(find.byType(NewOrderBanner), findsNothing);

      await tester.tap(find.byKey(const Key('shellTab-purchases')));
      await _settle(tester);
      expect(find.text('Compras'), findsWidgets);
    });
  });

  group('menú ☰ (CA-03)', () {
    Future<void> openDrawer(WidgetTester tester, ProviderContainer c) async {
      // Bajo reloj falso no se puede esperar el future del mock: se dispara
      // la carga y el tiempo se avanza con `_settle`.
      c.listen(currentMemberProvider, (_, __) {});
      await tester.pumpWidget(_app(
        c,
        const Scaffold(drawer: AppDrawer(), body: SizedBox()),
      ));
      await _settle(tester);
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await _settle(tester);
    }

    /// La lista del menú es más alta que el viewport de test: una entrada
    /// "existe" si aparece al desplazarse hasta ella.
    Future<bool> reveals(WidgetTester tester, String key) async {
      final scrollable = find.descendant(
          of: find.byType(Drawer), matching: find.byType(Scrollable));
      try {
        await tester.scrollUntilVisible(find.byKey(Key(key)), 200,
            scrollable: scrollable);
        return true;
      } catch (_) {
        return false;
      }
    }

    testWidgets('el Dueño ve Operación y Administración completas',
        (tester) async {
      final c = _container();
      await openDrawer(tester, c);
      // Cabecera = quién soy, con su rol.
      expect(find.byKey(const Key('drawerProfile')), findsOneWidget);
      expect(find.textContaining('Dueño'), findsOneWidget);
      for (final key in [
        'drawerPos',
        'drawerSalesHistory',
        'drawerStoreOrders',
        'drawerInventory',
        'drawerGondola',
        'drawerPurchases',
        'drawerCash',
        'drawerCatalog',
        'drawerReports',
        'drawerMembers',
        'drawerPreferences',
        'drawerSubscription',
      ]) {
        expect(await reveals(tester, key), isTrue, reason: key);
      }
      expect(find.text('ADMINISTRACIÓN'), findsOneWidget);
      // El mock SaaS trata a los correos @nexus.mx como fundadores (D1/D7 de
      // 14.2): la sección Sistema aparece; para un comerciante no existe.
      expect(await reveals(tester, 'drawerFounders'), isTrue);
    });

    testWidgets('el Encargado administra sin ver la suscripción (D10)',
        (tester) async {
      final c = _container(email: _manager);
      await openDrawer(tester, c);
      expect(await reveals(tester, 'drawerReports'), isTrue);
      expect(await reveals(tester, 'drawerMembers'), isTrue);
      expect(await reveals(tester, 'drawerPreferences'), isTrue);
      expect(await reveals(tester, 'drawerSubscription'), isFalse);
      expect(await reveals(tester, 'drawerClone'), isFalse);
    });

    testWidgets('el Cajero no tiene sección de Administración ni Compras',
        (tester) async {
      final c = _container(email: _cashier);
      await openDrawer(tester, c);
      expect(find.byKey(const Key('drawerPos')), findsOneWidget);
      expect(find.byKey(const Key('drawerSalesHistory')), findsOneWidget);
      expect(find.byKey(const Key('drawerStoreOrders')), findsOneWidget);
      expect(find.byKey(const Key('drawerCash')), findsOneWidget);
      expect(find.byKey(const Key('drawerInventory')), findsOneWidget);
      expect(find.byKey(const Key('drawerGondola')), findsNothing);
      expect(find.byKey(const Key('drawerPurchases')), findsNothing);
      expect(find.byKey(const Key('drawerCatalog')), findsNothing);
      expect(find.text('ADMINISTRACIÓN'), findsNothing);
      expect(find.byKey(const Key('drawerReports')), findsNothing);
      expect(find.byKey(const Key('drawerMembers')), findsNothing);
      expect(find.byKey(const Key('drawerSubscription')), findsNothing);
    });

    testWidgets('el Almacenista sólo ve inventario y compras', (tester) async {
      final c = _container(email: _warehouse);
      await openDrawer(tester, c);
      expect(find.byKey(const Key('drawerInventory')), findsOneWidget);
      expect(find.byKey(const Key('drawerGondola')), findsOneWidget);
      expect(find.byKey(const Key('drawerPurchases')), findsOneWidget);
      expect(find.byKey(const Key('drawerPos')), findsNothing);
      expect(find.byKey(const Key('drawerSalesHistory')), findsNothing);
      expect(find.byKey(const Key('drawerStoreOrders')), findsNothing);
      expect(find.byKey(const Key('drawerCash')), findsNothing);
      expect(find.text('ADMINISTRACIÓN'), findsNothing);
    });
  });

  group('Inicio recortado (CA-05)', () {
    testWidgets('el Cajero ve ventas y caja, sin ganancia ni por pagar',
        (tester) async {
      final c = _container(email: _cashier);
      _tallViewport(tester);
      await tester.pumpWidget(_routerApp(c));
      await _settle(tester);

      expect(find.text('CÓMO VA EL DÍA'), findsOneWidget);
      expect(find.byKey(const Key('homeSalesCard')), findsOneWidget);
      expect(find.byKey(const Key('homeCashCard')), findsOneWidget);
      expect(find.byKey(const Key('homeMarginCard')), findsNothing);
      expect(find.byKey(const Key('homePayables')), findsNothing);
      expect(find.byKey(const Key('homeWebOrdersCard')), findsOneWidget);
      // Acciones rápidas: la selección por defecto (vender · agregar ·
      // ajustar) se recorta a lo permitido y **no se rellena** (QA Sep 23):
      // por eso "Vitrina web" ya no se cuela encima de Pedidos web.
      expect(c.read(visibleQuickActionsProvider), [QuickActionId.sell]);
      expect(find.byKey(const Key('homeActionAddProduct')), findsNothing);
      expect(find.byKey(const Key('homeActionAdjustStock')), findsNothing);
    });

    testWidgets('el Almacenista se queda con acciones y alertas',
        (tester) async {
      final c = _container(email: _warehouse);
      _tallViewport(tester);
      await tester.pumpWidget(_routerApp(c));
      await _settle(tester);

      expect(find.text('CÓMO VA EL DÍA'), findsNothing);
      expect(find.byKey(const Key('homeSalesCard')), findsNothing);
      expect(find.byKey(const Key('homeWebOrdersCard')), findsNothing);
      expect(find.text('Últimas ventas'), findsNothing);
      expect(find.text('ALERTAS'), findsOneWidget);
      // De la selección por defecto conserva agregar y ajustar; "vender" se
      // cae por permiso y no se sustituye por nada.
      expect(c.read(visibleQuickActionsProvider), [
        QuickActionId.addProduct,
        QuickActionId.adjustStock,
      ]);
      expect(find.byKey(const Key('homeActionSell')), findsNothing);
    });

    testWidgets('el Dueño conserva la cuadrícula completa', (tester) async {
      final c = _container();
      _tallViewport(tester);
      await tester.pumpWidget(_routerApp(c));
      await _settle(tester);

      expect(find.byKey(const Key('homeSalesCard')), findsOneWidget);
      expect(find.byKey(const Key('homeMarginCard')), findsOneWidget);
      expect(find.byKey(const Key('homePayables')), findsOneWidget);
      expect(find.byKey(const Key('homeCashCard')), findsOneWidget);
      expect(c.read(visibleQuickActionsProvider),
          QuickActionDefinition.defaultSelection);
    });
  });

  group('acciones rápidas respetan la elección (QA Sep 23)', () {
    test('lo elegido es lo que se ve; sin relleno automático', () async {
      final c = _container(email: _cashier);
      await _loadMe(c);

      // El cajero deja sólo "Vitrina web": no reaparece "Vender".
      await c
          .read(quickActionsProvider.notifier)
          .setActions([QuickActionId.webCatalog]);
      expect(c.read(visibleQuickActionsProvider), [QuickActionId.webCatalog]);

      // Y si todo lo elegido le queda prohibido, entra una permitida: la
      // sección no se queda sin una sola acción.
      await c
          .read(quickActionsProvider.notifier)
          .setActions([QuickActionId.newPurchase]);
      expect(c.read(visibleQuickActionsProvider), [QuickActionId.sell]);
    });

    test('el Dueño ve exactamente lo que eligió, aunque sea una sola', () async {
      final c = _container();
      await _loadMe(c);
      await c
          .read(quickActionsProvider.notifier)
          .setActions([QuickActionId.gondola]);
      expect(c.read(visibleQuickActionsProvider), [QuickActionId.gondola]);
    });
  });

  group('avisos por permiso (CA-12)', () {
    test('el filtro sigue el permiso del dato que origina cada aviso', () {
      final items = [
        for (final kind in NotificationKind.values)
          StoreNotification(
            id: kind.name,
            kind: kind,
            title: kind.name,
            body: '',
            createdAt: _now,
            isRead: false,
          ),
      ];
      List<String> visible(Set<String> permissions) =>
          NotificationsNotifier.filterByPermissions(items, permissions)
              .map((n) => n.id)
              .toList();

      expect(visible(Permissions.all).length, 4);
      // Cajero: stock y pedidos web; ni cuentas por pagar ni hitos.
      expect(visible({Permissions.inventoryView, Permissions.salesView}),
          ['lowStock', 'whatsappOrder']);
      // Almacenista: stock y cuentas por pagar; nada de pedidos.
      expect(visible({Permissions.inventoryView, Permissions.purchasesView}),
          ['lowStock', 'payableDue']);
      expect(visible(const {}), isEmpty);
    });

    test('la campana del Almacenista no cuenta pedidos web', () async {
      final c = _container(email: _warehouse);
      await _loadMe(c);
      c.listen(notificationsProvider, (_, __) {});
      final items = await c.read(notificationsProvider.future);
      expect(items.map((n) => n.kind),
          isNot(contains(NotificationKind.whatsappOrder)));
      expect(items.map((n) => n.kind), contains(NotificationKind.lowStock));
    });
  });

  group('router (CA-06)', () {
    test('cada ruta administrativa exige su permiso', () {
      expect(requiredPermissionFor(AppRoutes.reports),
          Permissions.reportsViewBasic);
      expect(requiredPermissionFor(AppRoutes.manageMembers),
          Permissions.settingsManageUsers);
      expect(requiredPermissionFor(AppRoutes.managePermissions),
          Permissions.settingsManageUsers);
      expect(requiredPermissionFor(AppRoutes.preferences),
          Permissions.settingsManageStore);
      expect(requiredPermissionFor(AppRoutes.categories),
          Permissions.settingsManageStore);
      expect(requiredPermissionFor(AppRoutes.catalogShare),
          Permissions.settingsManageStore);
      expect(requiredPermissionFor(AppRoutes.purchases),
          Permissions.purchasesView);
      expect(requiredPermissionFor(AppRoutes.purchaseCreate),
          Permissions.purchasesCreate);
      expect(requiredPermissionFor(AppRoutes.sales), Permissions.salesCheckout);
      expect(requiredPermissionFor(AppRoutes.cash), Permissions.cashView);
      expect(requiredPermissionFor(AppRoutes.salesHistory),
          Permissions.salesView);
      expect(requiredPermissionFor('/ventas/historial/abc'),
          Permissions.salesView);
      expect(requiredPermissionFor(AppRoutes.gondola),
          Permissions.inventoryAdjustStock);
      expect(requiredPermissionFor(AppRoutes.import),
          Permissions.inventoryCreate);
      expect(requiredPermissionFor('/dashboard/inventory/products/p1/edit'),
          Permissions.inventoryEditPrice);
      // Libres para cualquier rol.
      expect(requiredPermissionFor(AppRoutes.home), isNull);
      expect(requiredPermissionFor(AppRoutes.inventory), isNull);
      expect(requiredPermissionFor('/dashboard/inventory/products/p1'), isNull);
      expect(requiredPermissionFor(AppRoutes.account), isNull);
      expect(requiredPermissionFor(AppRoutes.accountCommissions), isNull);
    });

    testWidgets('un Cajero que entra a Reportes por deep link vuelve a Inicio',
        (tester) async {
      final c = _container(email: _cashier);
      await tester.pumpWidget(_routerApp(c));
      await _settle(tester);

      final router = c.read(appRouterProvider);
      router.go(AppRoutes.reports);
      await _settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path,
          AppRoutes.home);

      // Y una ruta que sí es suya se respeta.
      router.go(AppRoutes.salesHistory);
      await _settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path,
          AppRoutes.salesHistory);
    });

    testWidgets('el Dueño entra a Reportes y a Usuarios', (tester) async {
      final c = _container();
      await tester.pumpWidget(_routerApp(c));
      await _settle(tester);

      final router = c.read(appRouterProvider);
      router.go(AppRoutes.manageMembers);
      await _settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path,
          AppRoutes.manageMembers);
    });
  });

  group('banner de morosidad (A9)', () {
    test('pagar es del Dueño: el resto no ve "Pagar ahora"', () async {
      final cashier = _container(email: _cashier);
      await _loadMe(cashier);
      expect(cashier.read(canSeeSubscriptionProvider), isFalse);

      final owner = _container();
      await _loadMe(owner);
      expect(owner.read(canSeeSubscriptionProvider), isTrue);
    });
  });
}
