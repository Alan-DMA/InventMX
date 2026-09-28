import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/router/app_router.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/features/account/data/operating_warehouse_store.dart';
import 'package:nexus_app/features/account/presentation/account_provider.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/management/data/management_repository.dart';
import 'package:nexus_app/features/management/presentation/management_provider.dart'
    show managementRepositoryProvider;
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart'
    show WarehouseOption, warehousesProvider;
import 'package:nexus_app/features/onboarding/presentation/onboarding_provider.dart';
import 'package:nexus_app/features/saas_admin/data/saas_repository.dart';
import 'package:nexus_app/features/saas_admin/domain/subscription.dart';
import 'package:nexus_app/features/saas_admin/presentation/hard_lock_screen.dart';
import 'package:nexus_app/features/saas_admin/presentation/saas_provider.dart';
import 'package:nexus_app/features/saas_admin/presentation/subscription_screen.dart';
import 'package:nexus_app/features/purchases/data/purchases_repository.dart';
import 'package:nexus_app/features/purchases/presentation/purchases_provider.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/store_orders_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/store_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/store_orders_provider.dart';
import 'package:nexus_app/features/dashboard/data/dashboard_repository.dart';
import 'package:nexus_app/features/dashboard/presentation/dashboard_provider.dart';

/// Suscripción prepago (P9–P13) sobre el router real con el mock: gracia con
/// acceso completo (P10), sólo lectura manual, suspensión que deja entrar y
/// sólo ve su suscripción, liberación al reactivar, y el menú sin panel de
/// fundadores (vive en su propia app web, P1). Con `now` = 14 sep 2026.
void main() {
  final now = DateTime(2026, 9, 14);

  Future<(GoRouterHandle, SaasRepositoryMock)> pumpApp(
    WidgetTester tester, {
    int daysUntilDue = 20,
    SubscriptionStatus? manualStatus,
    RenewalChannel renewalChannel = RenewalChannel.none,
    String email = 'sol@tiendita.mx',
  }) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mock = SaasRepositoryMock(
      currentEmail: email,
      latency: Duration.zero,
      now: () => now,
      daysUntilDue: daysUntilDue,
      manualStatus: manualStatus,
      renewalChannel: renewalChannel,
    );
    final handle = GoRouterHandle();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Pedidos web: el shell abre el canal en vivo; en tests, stream vacío.
          orderEventsProvider.overrideWithValue(const Stream<OrderEvent>.empty()),
          // Personas/roles reales desde la Fase B (Sep 21): mock en tests.
          managementRepositoryProvider.overrideWith((ref) => ManagementRepositoryMock(
              currentEmail: ref.watch(currentUserNameProvider) ?? 'demo@nexus.mx')),
          storeOrdersRepositoryProvider
              .overrideWithValue(StoreOrdersRepositoryMock(latency: Duration.zero)),
          sessionProvider.overrideWith((ref) => true),
          onboardingCompleteProvider.overrideWith((ref) => true),
          currentUserNameProvider.overrideWith((ref) => email),
          inventoryRepositoryProvider.overrideWithValue(InventoryRepositoryMock()),
          saasRepositoryProvider.overrideWithValue(mock),
          clockProvider.overrideWithValue(() => now),
          // Hive no está inicializado en tests: almacén operativo en memoria.
          operatingWarehouseStoreProvider.overrideWithValue(OperatingWarehouseStoreMemory()),
          authRepositoryProvider.overrideWithValue(AuthRepositoryMock(storage: SecureStorage())),
          warehousesProvider.overrideWith((ref) async => const [
                WarehouseOption(id: 'wh-001', name: 'Almacén Principal', isDefault: true),
              ]),
          salesRepositoryProvider.overrideWith((ref) => SalesRepositoryMock(clock: () => now)),
          purchasesRepositoryProvider.overrideWithValue(PurchasesRepositoryMock()),
          dashboardRepositoryProvider.overrideWithValue(DashboardRepositoryMock(now: now)),
        ],
        child: Consumer(
          builder: (_, ref, __) {
            final router = ref.watch(appRouterProvider);
            handle.router = router;
            handle.container = ProviderScope.containerOf(_);
            return MaterialApp.router(theme: AppTheme.dark, routerConfig: router);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (handle, mock);
  }

  testWidgets('P10: en gracia el banner dice cuántos días quedan y la fecha; todo sigue funcionando',
      (tester) async {
    // Venció el 10 sep → gracia hasta el 20 sep (6 días)
    final (handle, _) = await pumpApp(tester, daysUntilDue: -4);
    expect(find.byKey(const Key('softLockBanner')), findsOneWidget);
    expect(find.text('Suscripción vencida · 6 días de gracia'), findsOneWidget);
    expect(find.textContaining('Todo funciona normal hasta el 20 sep 2026'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    // Nueva compra NO se bloquea en gracia
    handle.router!.push(AppRoutes.purchases);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    expect(find.text('Tu cuenta está en solo lectura'), findsNothing);
  });

  testWidgets('en gracia, "Ver" lleva a Mi suscripción', (tester) async {
    await pumpApp(tester, daysUntilDue: -4);
    await tester.tap(find.byKey(const Key('softLockPayNow')));
    await tester.pumpAndSettle();
    expect(find.byType(MySubscriptionScreen), findsOneWidget);
    expect(find.text('En gracia'), findsOneWidget); // chip
  });

  testWidgets('A9: un Cajero en gracia ve el aviso sin botón y con el recado para quien administra',
      (tester) async {
    await pumpApp(tester, daysUntilDue: -4, email: 'jose.ramirez@nexus.mx');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('softLockBanner')), findsOneWidget);
    expect(find.byKey(const Key('softLockPayNow')), findsNothing);
    expect(find.textContaining('Avísale a quien administra la tienda'), findsOneWidget);
    await tester.tap(find.byKey(const Key('softLockBannerTitle')));
    await tester.pumpAndSettle();
    expect(find.byType(MySubscriptionScreen), findsNothing);
  });

  testWidgets('vigente: no hay banner', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('softLockBanner')), findsNothing);
  });

  testWidgets('sólo lectura manual: banner y "Nueva compra" explica y ofrece ver la suscripción',
      (tester) async {
    final (handle, _) = await pumpApp(tester, manualStatus: SubscriptionStatus.softLock);
    expect(find.byKey(const Key('softLockBannerTitle')), findsOneWidget);
    expect(find.text('Solo lectura'), findsOneWidget);
    handle.router!.push(AppRoutes.purchases);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    expect(find.text('Tu cuenta está en solo lectura'), findsOneWidget);
    await tester.tap(find.byKey(const Key('writeGatePayNow')));
    await tester.pumpAndSettle();
    expect(find.byType(MySubscriptionScreen), findsOneWidget);
  });

  testWidgets('suspendida: todo va a /locked, sin formas de pago; sólo deja ver la suscripción',
      (tester) async {
    // Venció el 30 ago → gracia hasta el 9 sep → suspendida
    final (handle, _) = await pumpApp(tester, daysUntilDue: -15);
    expect(find.byType(HardLockScreen), findsOneWidget);
    expect(find.textContaining('venció el 30 ago 2026'), findsOneWidget);
    expect(find.textContaining('No se borra nada'), findsOneWidget);
    expect(find.byKey(const Key('hardLockContactUs')), findsOneWidget);
    expect(find.byKey(const Key('hardLockRenewButton')), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

    handle.router!.go(AppRoutes.sales);
    await tester.pumpAndSettle();
    expect(find.byType(HardLockScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('hardLockSeeSubscription')));
    await tester.pumpAndSettle();
    expect(find.byType(MySubscriptionScreen), findsOneWidget);
    expect(find.text('Suspendida'), findsOneWidget); // chip
  });

  testWidgets('con el canal de Google Play encendido aparece "Renovar" y usa el punto de conexión',
      (tester) async {
    await pumpApp(tester, daysUntilDue: -15, renewalChannel: RenewalChannel.googlePlay);
    expect(find.byKey(const Key('hardLockRenewButton')), findsOneWidget);
    expect(find.text(r'Renovar por $399.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('hardLockRenewButton')));
    await tester.pumpAndSettle();
    expect(find.text('Renovación en camino'), findsOneWidget);
  });

  testWidgets('al renovar (soporte o pago) la suspensión se libera sola', (tester) async {
    final (handle, mock) = await pumpApp(tester, daysUntilDue: -15);
    expect(find.byType(HardLockScreen), findsOneWidget);

    mock.daysUntilDue = 30; // soporte confirmó un pago en el panel
    await tester.runAsync(() async {
      handle.container!.invalidate(subscriptionProvider);
      await handle.container!.read(subscriptionProvider.future);
    });
    await tester.pumpAndSettle();
    expect(handle.container!.read(subscriptionStatusProvider), SubscriptionStatus.active);
    expect(find.byType(HardLockScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const Key('softLockBanner')), findsNothing);
  });

  testWidgets('menú ☰: "Mi suscripción" abre la pantalla informativa y ya no hay panel de fundadores',
      (tester) async {
    await pumpApp(tester, email: 'eduardo@nexus.mx');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('homeDrawerButton')));
    await tester.pumpAndSettle();
    expect(find.text('ADMINISTRACIÓN'), findsOneWidget);
    expect(find.text('SISTEMA'), findsNothing);
    expect(find.byKey(const Key('drawerFounders')), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('drawerSubscription')),
      200,
      scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)),
    );
    await tester.tap(find.byKey(const Key('drawerSubscription')));
    await tester.pumpAndSettle();
    expect(find.byType(MySubscriptionScreen), findsOneWidget);
    expect(find.byKey(const Key('subscriptionRenewalSoon')), findsOneWidget);
    expect(find.textContaining('SPEI'), findsNothing);
    expect(find.textContaining('OXXO'), findsNothing);
  });
}

/// Acceso al router/container creado dentro del árbol.
class GoRouterHandle {
  dynamic router;
  ProviderContainer? container;
}
