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
import 'package:nexus_app/features/auth/presentation/login_screen.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart'
    show WarehouseOption, warehousesProvider;
import 'package:nexus_app/features/onboarding/presentation/onboarding_provider.dart';
import 'package:nexus_app/features/onboarding/presentation/onboarding_wizard_screen.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/whatsapp_catalog_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/public_catalog_screen.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/whatsapp_catalog_provider.dart';

/// app_router_redirect_test — CA-04, CA-05, CA-08, CA-09
///
/// El router ahora tiene triple redirect:
///   sin sesión            → /login
///   sesión + sin onb.     → /onboarding
///   sesión + onb. completo → /dashboard
void main() {
  Widget buildApp({
    required bool hasSession,
    required bool onboardingDone,
  }) {
    return ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => hasSession),
        onboardingCompleteProvider.overrideWith((ref) => onboardingDone),
        inventoryRepositoryProvider.overrideWithValue(InventoryRepositoryMock()),
        // El Dashboard (Fase 3) lee el almacén operativo en el saludo — sin
        // esto golpearía Hive real, que no está inicializado en este test.
        operatingWarehouseStoreProvider
            .overrideWithValue(OperatingWarehouseStoreMemory()),
        // El almacén operativo ahora persiste en el backend real.
        authRepositoryProvider
            .overrideWithValue(AuthRepositoryMock(storage: SecureStorage())),
        warehousesProvider.overrideWith((ref) async => const [
              WarehouseOption(
                  id: 'wh-001', name: 'Almacén Principal', isDefault: true),
            ]),
      ],
      child: Consumer(
        builder: (_, ref, __) {
          final router = ref.watch(appRouterProvider);
          return MaterialApp.router(
            theme: AppTheme.dark,
            routerConfig: router,
          );
        },
      ),
    );
  }

  group('AppRouter — triple redirect reactivo', () {
    testWidgets(
      'CA-04: Sin sesión → muestra LoginScreen',
      (tester) async {
        await tester.pumpWidget(
          buildApp(hasSession: false, onboardingDone: false),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );

    testWidgets(
      'CA-09: Con sesión pero onboarding incompleto → muestra OnboardingWizardScreen',
      (tester) async {
        await tester.pumpWidget(
          buildApp(hasSession: true, onboardingDone: false),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(OnboardingWizardScreen), findsOneWidget);
      },
    );

    testWidgets(
      'CA-05: Con sesión y onboarding completo → muestra Dashboard, no Login',
      (tester) async {
        await tester.pumpWidget(
          buildApp(hasSession: true, onboardingDone: true),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(OnboardingWizardScreen), findsNothing);
        // Con el nuevo ShellRoute, el dashboard muestra el NavigationBar
        expect(find.byType(NavigationBar), findsOneWidget);
      },
    );
  });

  group('AppRouter — vitrina pública (Tarea 13.2)', () {
    testWidgets('/tienda/{slug} abre sin sesión: no redirige al login',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => false),
            onboardingCompleteProvider.overrideWith((ref) => false),
            catalogStoreNameProvider
                .overrideWith((_) async => 'Abarrotes Don Pepe'),
            whatsappCatalogRepositoryProvider.overrideWithValue(
              WhatsappCatalogRepositoryMock(
                storeName: 'Abarrotes Don Pepe',
                latency: Duration.zero,
              ),
            ),
          ],
          child: Consumer(
            builder: (_, ref, __) {
              final router = ref.watch(appRouterProvider);
              // Simula abrir el enlace compartido directamente.
              router.go(AppRoutes.publicCatalogPath('abarrotes-don-pepe'));
              return MaterialApp.router(
                theme: AppTheme.dark,
                routerConfig: router,
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(PublicCatalogScreen), findsOneWidget);
      expect(find.text('Abarrotes Don Pepe'), findsOneWidget);
    });
  });
}
