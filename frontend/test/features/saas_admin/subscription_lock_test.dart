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
import 'package:nexus_app/features/saas_admin/presentation/founder_admin_dashboard_screen.dart';
import 'package:nexus_app/features/saas_admin/presentation/hard_lock_screen.dart';
import 'package:nexus_app/features/saas_admin/presentation/saas_provider.dart';
import 'package:nexus_app/features/saas_admin/presentation/subscription_checkout_screen.dart';
import 'package:nexus_app/features/purchases/data/purchases_repository.dart';
import 'package:nexus_app/features/purchases/presentation/purchases_provider.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/store_orders_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/store_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/store_orders_provider.dart';
import 'package:nexus_app/features/dashboard/data/dashboard_repository.dart';
import 'package:nexus_app/features/dashboard/presentation/dashboard_provider.dart';

/// Tarea 14.2.3 — CA-08 (puerta /admin), CA-09 (banner Soft Lock + guarda),
/// CA-10 (Hard Lock: redirect, salida a pago, liberación al reactivar).
/// Corre sobre el router real con el mock del SaaS.
void main() {
  final now = DateTime(2026, 9, 14);

  Future<(GoRouterHandle, SaasRepositoryMock)> pumpApp(
    WidgetTester tester, {
    required String tenant,
    String email = 'sol@tiendita.mx',
  }) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mock = SaasRepositoryMock(
      currentEmail: email,
      currentTenantId: tenant,
      latency: Duration.zero,
      now: () => now,
    );
    final handle = GoRouterHandle();
    await tester.pumpWidget(
      ProviderScope(
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
          sessionProvider.overrideWith((ref) => true),
          onboardingCompleteProvider.overrideWith((ref) => true),
          currentUserNameProvider.overrideWith((ref) => email),
          inventoryRepositoryProvider.overrideWithValue(InventoryRepositoryMock()),
          saasRepositoryProvider.overrideWithValue(mock),
          clockProvider.overrideWithValue(() => now),
          // Hive no está inicializado en tests: el almacén operativo usa el
          // doble en memoria.
          operatingWarehouseStoreProvider
              .overrideWithValue(OperatingWarehouseStoreMemory()),
          // El almacén operativo ahora persiste en el backend real.
          authRepositoryProvider
              .overrideWithValue(AuthRepositoryMock(storage: SecureStorage())),
          warehousesProvider.overrideWith((ref) async => const [
                WarehouseOption(
                    id: 'wh-001', name: 'Almacén Principal', isDefault: true),
              ]),
          // El Dashboard también pide "Últimas ventas" — sin esto golpearía
          // la red real desde Sep 2026 (salesRepositoryProvider ya no es
          // Mock por defecto).
          salesRepositoryProvider.overrideWith((ref) => SalesRepositoryMock(clock: () => now)),
          // Mismo motivo para Compras: `purchasesRepositoryProvider` apunta a
          // `PurchasesRepositoryImpl` desde la octava sesión (Sep 19).
          purchasesRepositoryProvider.overrideWithValue(PurchasesRepositoryMock()),
          // El Dashboard pide métricas al backend real — en tests de integración
          // se usa el mock determinista.
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

  testWidgets('CA-09: Soft Lock muestra el banner con día N/10 y fecha de bloqueo; "Pagar ahora" abre Mi suscripción', (tester) async {
    await pumpApp(tester, tenant: 't-lupita');
    expect(find.byKey(const Key('softLockBanner')), findsOneWidget);
    expect(find.text('Solo lectura · día 4 de 10'), findsOneWidget);
    // Lupita venció hace 4 días (10 sep) → bloqueo total el 21 sep
    expect(find.textContaining('Bloqueo total el 21 sep 2026'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.byKey(const Key('softLockPayNow')));
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionCheckoutScreen), findsOneWidget);
  });

  testWidgets('A9: un Cajero ve el banner de Soft Lock sin "Pagar ahora" y con el aviso a quien administra', (tester) async {
    await pumpApp(tester, tenant: 't-lupita', email: 'jose.ramirez@nexus.mx');
    // Quién soy (rol) carga con retardo del mock de Gestión.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('softLockBanner')), findsOneWidget);
    expect(find.text('Solo lectura · día 4 de 10'), findsOneWidget);
    expect(find.byKey(const Key('softLockPayNow')), findsNothing);
    expect(find.textContaining('avísale a quien administra la tienda'), findsOneWidget);

    // Tocar el banner tampoco lo manda a una pantalla que el router rebotaría.
    await tester.tap(find.byKey(const Key('softLockBannerTitle')));
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionCheckoutScreen), findsNothing);
  });

  testWidgets('CA-09: sin morosidad no hay banner', (tester) async {
    await pumpApp(tester, tenant: 't-sol');
    expect(find.byKey(const Key('softLockBanner')), findsNothing);
  });

  testWidgets('CA-09: en Soft Lock, "Nueva compra" no abre el flujo: explica y ofrece ir a pagar', (tester) async {
    final (handle, _) = await pumpApp(tester, tenant: 't-lupita');
    handle.router!.push(AppRoutes.purchases);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsWidgets);

    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    expect(find.text('Tu cuenta está en solo lectura'), findsOneWidget);
    await tester.tap(find.byKey(const Key('writeGatePayNow')));
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionCheckoutScreen), findsOneWidget);
  });

  testWidgets('CA-10: Hard Lock redirige todo el dashboard a /locked; solo deja pasar Mi suscripción', (tester) async {
    final (handle, _) = await pumpApp(tester, tenant: 't-esquina');
    expect(find.byType(HardLockScreen), findsOneWidget);
    expect(find.byKey(const Key('hardLockTitle')), findsOneWidget);
    expect(find.text('\$399.00 MXN'), findsOneWidget);
    expect(find.textContaining('No se borra nada'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // Intentar ir a ventas → sigue bloqueado
    handle.router!.go(AppRoutes.sales);
    await tester.pumpAndSettle();
    expect(find.byType(HardLockScreen), findsOneWidget);

    // Salida a pagar
    await tester.tap(find.byKey(const Key('hardLockPayButton')));
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionCheckoutScreen), findsOneWidget);
    expect(find.text('Bloqueada'), findsOneWidget); // chip
  });

  testWidgets('CA-10: al aprobar el pago (fundador) el bloqueo se libera solo', (tester) async {
    final (handle, mock) = await pumpApp(tester, tenant: 't-esquina', email: 'eduardo@nexus.mx');
    expect(find.byType(HardLockScreen), findsOneWidget);

    // Un fundador aprueba el aviso pendiente de La Esquina en el backend (mock).
    // runAsync: el mock usa Future.delayed, que no avanza bajo el reloj falso.
    await tester.runAsync(() async {
      final inbox = await mock.getValidationInbox();
      final item = inbox.firstWhere((i) => i.tenantId == 't-esquina');
      await mock.approveValidation(item.validation.id);
    });

    // La app relee la suscripción → ACTIVE → el router libera /locked
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

  testWidgets('CA-08: /admin rebota a inventario sin saas.manage y abre con él', (tester) async {
    final (handle, _) = await pumpApp(tester, tenant: 't-sol');
    handle.router!.go(AppRoutes.founderAdmin);
    await tester.pumpAndSettle();
    expect(find.byType(FounderAdminDashboardScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    final (handle2, _) = await pumpApp(tester, tenant: 't-sol', email: 'eduardo@nexus.mx');
    handle2.router!.go(AppRoutes.founderAdmin);
    await tester.pumpAndSettle();
    expect(find.byType(FounderAdminDashboardScreen), findsOneWidget);
  });

  testWidgets('menú ☰: suscripción y panel de fundadores viven en el menú, no en Mi perfil (CA-03/CA-04)', (tester) async {
    await pumpApp(tester, tenant: 't-sol', email: 'eduardo@nexus.mx');
    // Los datos del miembro (rol, permisos) cargan con retardo del mock.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Mi perfil: sólo lo propio, ni siquiera para el Dueño fundador.
    await tester.tap(find.byKey(const Key('homeAccountButton')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Mi perfil'), findsOneWidget);
    expect(find.byKey(const Key('accountRowSubscription')), findsNothing);
    expect(find.byKey(const Key('accountRowSystem')), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Menú ☰: Administración con "Mi suscripción" y Sistema con fundadores.
    await tester.tap(find.byKey(const Key('homeDrawerButton')));
    await tester.pumpAndSettle();
    expect(find.text('ADMINISTRACIÓN'), findsOneWidget);
    expect(find.byKey(const Key('drawerSubscription')), findsOneWidget);
    // Sistema queda al final de la lista del menú: hay que bajar.
    await tester.scrollUntilVisible(
      find.byKey(const Key('drawerFounders')),
      200,
      scrollable: find.descendant(
          of: find.byType(Drawer), matching: find.byType(Scrollable)),
    );
    expect(find.byKey(const Key('drawerFounders')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('drawerSubscription')),
      -200,
      scrollable: find.descendant(
          of: find.byType(Drawer), matching: find.byType(Scrollable)),
    );

    await tester.tap(find.byKey(const Key('drawerSubscription')));
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionCheckoutScreen), findsOneWidget);
  });
}

/// Acceso al router/container creado dentro del árbol.
class GoRouterHandle {
  dynamic router;
  ProviderContainer? container;
}
