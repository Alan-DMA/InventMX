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
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/dashboard/data/dashboard_repository.dart';
import 'package:nexus_app/features/dashboard/presentation/dashboard_provider.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart'
    show WarehouseOption, warehousesProvider;
import 'package:nexus_app/features/management/data/management_repository.dart';
import 'package:nexus_app/features/management/presentation/management_provider.dart'
    show managementRepositoryProvider;
import 'package:nexus_app/features/onboarding/presentation/onboarding_provider.dart';
import 'package:nexus_app/features/purchases/data/purchases_repository.dart';
import 'package:nexus_app/features/purchases/presentation/purchases_provider.dart';
import 'package:nexus_app/features/saas_admin/data/saas_repository.dart';
import 'package:nexus_app/features/saas_admin/presentation/saas_provider.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/support/data/support_repository.dart';
import 'package:nexus_app/features/support/presentation/support_provider.dart';
import 'package:nexus_app/features/support/presentation/support_unread_poller.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/store_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/store_orders_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/store_orders_provider.dart';

/// App completa (router real) con mocks, para las pruebas del Centro de
/// soporte, etapa 2b. Mismo arnés que `subscription_lock_test.dart`, más
/// Soporte, la bandera de contraseña pendiente y un almacén en memoria.
class SupportApp {
  GoRouter? router;
  ProviderContainer? container;
  late SupportRepositoryMock support;
  late MemoryStorage storage;
}

/// Almacén seguro en memoria (Hive no está inicializado en tests).
class MemoryStorage extends SecureStorage {
  final Map<String, String> values = {};

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    values['access'] = accessToken;
    values['refresh'] = refreshToken;
  }

  @override
  Future<void> saveUserEmail(String email) async => values['email'] = email;

  @override
  Future<String?> readUserEmail() async => values['email'];

  @override
  Future<void> saveMustChangePassword(bool value) async =>
      value ? values['must_change'] = 'true' : values.remove('must_change');

  @override
  Future<bool> readMustChangePassword() async => values['must_change'] == 'true';

  @override
  Future<void> clearSession() async => values.clear();

  @override
  Future<void> clearAll() async => values.clear();

  @override
  Future<bool> hasSession() async => values.containsKey('access');
}

Future<SupportApp> pumpSupportApp(
  WidgetTester tester, {
  bool hasSession = true,
  bool mustChangePassword = false,
  int daysUntilDue = 20,
  String? abuseReason,
  String email = 'sol@tiendita.mx',
  SupportRepositoryMock? support,
  DateTime? now,
  // La consulta de respuestas: en 1 h por omisión para no cruzarse con los
  // demás tests; el que la prueba pide 60 s
  Duration pollEvery = const Duration(hours: 1),
}) async {
  final today = now ?? DateTime(2026, 9, 14);
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final app = SupportApp()
    ..support = support ?? SupportRepositoryMock(latency: Duration.zero, now: () => today)
    ..storage = MemoryStorage();
  final saas = SaasRepositoryMock(
    currentEmail: email,
    latency: Duration.zero,
    now: () => today,
    daysUntilDue: daysUntilDue,
    abuseReason: abuseReason,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderEventsProvider.overrideWithValue(const Stream<OrderEvent>.empty()),
        managementRepositoryProvider.overrideWith((ref) => ManagementRepositoryMock(
            currentEmail: ref.watch(currentUserNameProvider) ?? 'demo@nexus.mx')),
        storeOrdersRepositoryProvider.overrideWithValue(StoreOrdersRepositoryMock(latency: Duration.zero)),
        sessionProvider.overrideWith((ref) => hasSession),
        mustChangePasswordProvider.overrideWith((ref) => mustChangePassword),
        onboardingCompleteProvider.overrideWith((ref) => true),
        currentUserNameProvider.overrideWith((ref) => hasSession ? email : null),
        inventoryRepositoryProvider.overrideWithValue(InventoryRepositoryMock()),
        saasRepositoryProvider.overrideWithValue(saas),
        clockProvider.overrideWithValue(() => today),
        operatingWarehouseStoreProvider.overrideWithValue(OperatingWarehouseStoreMemory()),
        secureStorageProvider.overrideWithValue(app.storage),
        authRepositoryProvider.overrideWith((ref) => AuthRepositoryMock(storage: app.storage)),
        supportRepositoryProvider.overrideWithValue(app.support),
        supportPollIntervalProvider.overrideWithValue(pollEvery),
        warehousesProvider.overrideWith((ref) async => const [
              WarehouseOption(id: 'wh-001', name: 'Almacén Principal', isDefault: true),
            ]),
        salesRepositoryProvider.overrideWith((ref) => SalesRepositoryMock(clock: () => today)),
        purchasesRepositoryProvider.overrideWithValue(PurchasesRepositoryMock()),
        dashboardRepositoryProvider.overrideWithValue(DashboardRepositoryMock(now: today)),
      ],
      child: Consumer(
        builder: (context, ref, __) {
          final router = ref.watch(appRouterProvider);
          app.router = router;
          app.container = ProviderScope.containerOf(context);
          return MaterialApp.router(
            theme: AppTheme.dark,
            routerConfig: router,
            // Igual que en main.dart: insignias y avisos al día cada 60 s
            builder: (context, child) => SupportUnreadPoller(child: child!),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Los mocks simulan latencia con timers (p. ej. `/auth/me` tarda 400 ms):
  // se deja correr ese tiempo para que no queden timers pendientes.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  return app;
}

/// Navega y espera a que se asiente.
Future<void> goTo(WidgetTester tester, SupportApp app, String location) async {
  app.router!.go(location);
  await tester.pumpAndSettle();
}

/// Un recorrido corto del dueño del arnés: correo con el que entra el mock.
const demoOwnerEmail = 'demo@nexus.mx';

/// Ruta de inicio del tablero.
const homeRoute = AppRoutes.home;
