import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/login_provider.dart';
import '../../features/onboarding/presentation/onboarding_wizard_screen.dart';
import '../../features/onboarding/presentation/onboarding_provider.dart';
import '../../features/onboarding/presentation/pages/step4_success_page.dart';
import '../../features/dashboard/presentation/dashboard_shell.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/inventory/presentation/product_detail_screen.dart';
import '../../features/inventory/presentation/edit_product_screen.dart';
import '../../features/inventory/presentation/import_screen.dart';
import '../../features/inventory/presentation/gondola_scan_screen.dart';
import '../../features/inventory/presentation/inventory_provider.dart';
import '../../features/cash_treasury/presentation/cash_session_screen.dart';
import '../../features/sales_pos/presentation/checkout_screen.dart';

// ---------------------------------------------------------------------------
// Rutas nombradas
// ---------------------------------------------------------------------------

abstract final class AppRoutes {
  static const login = '/login';
  static const onboarding = '/onboarding';
  static const onboardingSuccess = '/onboarding/success';

  // Shell raíz del dashboard
  static const dashboard = '/dashboard';

  // Branches del ShellRoute
  static const inventory = '/dashboard/inventory';
  static const sales = '/dashboard/sales';
  static const cash = '/dashboard/cash';
  static const reports = '/dashboard/reports';

  // Detalle de producto
  static const productDetail = '/dashboard/inventory/products/:id';
  // Edición completa de producto
  static const productEdit = '/dashboard/inventory/products/:id/edit';

  // Importación desde Excel/CSV (Tarea 5.2)
  static const import = '/dashboard/inventory/import';

  // Modo Góndola — escaneo continuo (Tarea 5.2)
  static const gondola = '/dashboard/inventory/gondola';

  static String productDetailPath(String id) =>
      '/dashboard/inventory/products/$id';

  static String productEditPath(String id) =>
      '/dashboard/inventory/products/$id/edit';
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

/// GoRouter con triple redirect reactivo:
///   1. Sin sesión              → /login
///   2. Con sesión, sin onb.    → /onboarding
///   3. Con sesión + onb. done  → /dashboard/inventory
///
/// Usa StatefulShellRoute para que cada branch mantenga su propio
/// stack de navegación y la NavigationBar persista entre tabs.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _CompositeRefreshListenable(ref);

  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: refreshNotifier,
    redirect: (BuildContext context, GoRouterState routerState) {
      final hasSession = ref.read(sessionProvider);
      final onboardingDone = ref.read(onboardingCompleteProvider);
      final location = routerState.matchedLocation;

      // ── Sin sesión: siempre al login ──────────────────────────────────
      if (!hasSession) {
        return location == AppRoutes.login ? null : AppRoutes.login;
      }

      // ── Con sesión, onboarding incompleto ─────────────────────────────
      if (!onboardingDone) {
        final isOnboardingFlow = location == AppRoutes.onboarding ||
            location == AppRoutes.onboardingSuccess;
        return isOnboardingFlow ? null : AppRoutes.onboarding;
      }

      // ── Con sesión y onboarding completo ──────────────────────────────
      if (location == AppRoutes.login ||
          location == AppRoutes.onboarding ||
          location == AppRoutes.onboardingSuccess) {
        return AppRoutes.inventory;
      }

      return null;
    },
    routes: [
      // ── Auth ─────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (_, __) => const LoginScreen(),
      ),

      // ── Onboarding ───────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (_, __) => const OnboardingWizardScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingSuccess,
        name: 'onboarding-success',
        builder: (_, __) => const Step4SuccessPage(),
      ),

      // ── Dashboard con NavigationBar (ShellRoute) ─────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => DashboardShell(
          navigationShell: navigationShell,
        ),
        branches: [
          // Branch 0 — Inventario
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.inventory,
                name: 'inventory',
                builder: (_, __) => const InventoryScreen(),
                routes: [
                  // Importación desde Excel/CSV — Tarea 5.2
                  GoRoute(
                    path: 'import',
                    name: 'import',
                    builder: (_, __) => const ImportScreen(),
                  ),

                  // Modo Góndola — escaneo continuo — Tarea 5.2
                  GoRoute(
                    path: 'gondola',
                    name: 'gondola',
                    builder: (_, __) => const GondolaScanScreen(),
                  ),

                  // Detalle de producto — Subtarea 3.2.2
                  GoRoute(
                    path: 'products/:id',
                    name: 'product-detail',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return ProductDetailScreen(productId: id);
                    },
                    routes: [
                      // Edición completa de producto — Tarea 3.2.4
                      GoRoute(
                        path: 'edit',
                        name: 'product-edit',
                        builder: (context, state) {
                          final id = state.pathParameters['id']!;
                          // Resuelve el producto desde la caché del provider.
                          // En el flujo normal siempre viene de la ficha de
                          // detalle, por lo que el producto ya está en memoria.
                          final product = ref
                              .read(inventoryProvider)
                              .products
                              .where((p) => p.id == id)
                              .firstOrNull;
                          if (product == null) {
                            // Fallback: vuelve al detalle si no hay caché
                            return ProductDetailScreen(productId: id);
                          }
                          return EditProductScreen(product: product);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // Branch 1 — Ventas (Tarea 6.2)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.sales,
                name: 'sales',
                builder: (_, __) => const CheckoutScreen(),
              ),
            ],
          ),

          // Branch 2 — Caja (placeholder D9)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.cash,
                name: 'cash',
                builder: (_, __) => const CashSessionScreen(),
              ),
            ],
          ),

          // Branch 3 — Reportes (placeholder D15)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.reports,
                name: 'reports',
                builder: (_, __) => const ReportsPlaceholder(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(
        child: Text('Ruta no encontrada: ${state.error}'),
      ),
    ),
  );
});

// ---------------------------------------------------------------------------
// Listenable compuesto — notifica al router cuando CUALQUIERA de los dos
// StateProviders cambia (sesión u onboarding).
// ---------------------------------------------------------------------------

class _CompositeRefreshListenable extends ChangeNotifier {
  _CompositeRefreshListenable(Ref ref) {
    ref.listen(sessionProvider, (_, __) => notifyListeners());
    ref.listen(onboardingCompleteProvider, (_, __) => notifyListeners());
  }
}
