import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/login_provider.dart';
import '../../features/onboarding/presentation/onboarding_wizard_screen.dart';
import '../../features/onboarding/presentation/onboarding_provider.dart';
import '../../features/onboarding/presentation/pages/step4_success_page.dart';
import '../../features/dashboard/presentation/dashboard_shell.dart';
import '../../features/dashboard/presentation/home_dashboard_screen.dart';
import '../../features/dashboard/presentation/notifications_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/inventory/presentation/product_detail_screen.dart';
import '../../features/inventory/presentation/edit_product_screen.dart';
import '../../features/inventory/presentation/import_screen.dart';
import '../../features/inventory/presentation/gondola_scan_screen.dart';
import '../../features/inventory/presentation/inventory_provider.dart';
import '../../features/cash_treasury/presentation/cash_session_screen.dart';
import '../../features/sales_pos/presentation/checkout_screen.dart';
import '../../features/sales_pos/presentation/sales_kardex_screen.dart';
import '../../features/sales_pos/presentation/sale_receipt_screen.dart';
import '../../features/purchases/presentation/purchases_hub_screen.dart';
import '../../features/purchases/presentation/purchase_create_screen.dart';
import '../../features/dictation_diagnostic/presentation/dictation_diagnostic_screen.dart';
import '../../features/whatsapp_catalog/presentation/catalog_share_screen.dart';
import '../../features/whatsapp_catalog/presentation/order_ticket_screen.dart';
import '../../features/whatsapp_catalog/presentation/public_catalog_screen.dart';
import '../../features/whatsapp_catalog/presentation/store_order_detail_screen.dart';
import '../../features/whatsapp_catalog/presentation/store_orders_screen.dart';
import '../../features/account/presentation/account_screen.dart';
import '../../features/account/presentation/personal_data_screen.dart';
import '../../features/account/presentation/password_screen.dart';
import '../../features/account/presentation/operating_warehouse_screen.dart';
import '../../features/management/presentation/preferences_screen.dart';
import '../../features/management/presentation/warehouses_screen.dart';
import '../../features/management/presentation/categories_screen.dart';
import '../../features/management/presentation/members_screen.dart';
import '../../features/management/presentation/permissions_screen.dart';
import '../../features/saas_admin/domain/subscription.dart';
import '../../features/saas_admin/presentation/founder_admin_dashboard_screen.dart';
import '../../features/saas_admin/presentation/hard_lock_screen.dart';
import '../../features/saas_admin/presentation/saas_provider.dart';
import '../../features/saas_admin/presentation/subscription_checkout_screen.dart';
import '../../features/analytics/presentation/analytics_dashboard_screen.dart';

// ---------------------------------------------------------------------------
// Rutas nombradas
// ---------------------------------------------------------------------------

abstract final class AppRoutes {
  static const login = '/login';
  static const onboarding = '/onboarding';
  static const onboardingSuccess = '/onboarding/success';

  // Diagnóstico interno — prototipo CRF de dictado multi-ítem (Fase 3).
  // No enlazado desde la navegación real, solo por URL directa.
  static const dictationDiagnostic = '/diagnostic/dictation';

  // Shell raíz del dashboard
  static const dashboard = '/dashboard';

  // Branches del ShellRoute
  static const home = '/dashboard/home';
  static const notifications = '/dashboard/home/notifications';
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

  // Hub de Compras, Proveedores y CxP (Tarea 11.2)
  static const purchases = '/dashboard/inventory/purchases';
  static const purchaseCreate = '/dashboard/inventory/purchases/new';

  // Panel de difusión del catálogo digital (Tarea 13.2.3)
  static const catalogShare = '/dashboard/inventory/catalog';

  // Vitrina pública del catálogo — sin sesión (Tarea 13.2.1, RF-23)
  static const publicCatalog = '/tienda/:slug';

  // Cuenta: página índice a la que lleva el avatar, y sus sub-páginas.
  static const account = '/cuenta';
  static const accountData = '/cuenta/datos';
  static const accountPassword = '/cuenta/contrasena';
  static const accountWarehouse = '/cuenta/almacen';

  // Administración del propio comercio. Scope de un solo tenant — distinto
  // del panel de fundadores (`/admin`), que opera la plataforma.
  static const manageMembers = '/negocio/usuarios';
  static const managePermissions = '/negocio/usuarios/permisos';
  static const preferences = '/negocio/preferencias';
  static const warehouses = '/negocio/preferencias/almacenes';
  static const categories = '/negocio/preferencias/categorias';

  // Kardex de ventas (Fase 2). Fuera del shell: se entra desde Reportes,
  // el POS y el Dashboard, y el detalle cubre la barra de navegación.
  static const salesHistory = '/ventas/historial';
  static const saleDetail = '/ventas/historial/:id';
  static String saleDetailPath(String id) => '/ventas/historial/$id';

  // Pedidos web del tendero (plan del 20 sep 2026). Fuera del shell, como el
  // kardex: se entra desde Inicio (avisos / tarjeta), Ventas y el banner.
  static const storeOrders = '/ventas/pedidos';
  static const storeOrderDetail = '/ventas/pedidos/:folio';
  static String storeOrderPath(String folio) => '/ventas/pedidos/$folio';

  // Suscripción SaaS (Tarea 14.2). Fuera del shell: se alcanzan también
  // desde el bloqueo total por morosidad.
  static const subscription = '/subscription';
  static const founderAdmin = '/admin';
  static const locked = '/locked';

  static String publicCatalogPath(String slug) => '/tienda/$slug';

  // Ticket de un pedido registrado — enlace que va en el chat (13.2.2)
  static String publicOrderPath(String slug, String folio) =>
      '/tienda/$slug/pedido/$folio';

  static String productDetailPath(String id) =>
      '/dashboard/inventory/products/$id';

  static String productEditPath(String id) =>
      '/dashboard/inventory/products/$id/edit';
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

/// GoRouter con redirect reactivo:
///   1. Sin sesión              → /login
///   2. Con sesión, sin onb.    → /onboarding
///   3. Con sesión + onb. done  → /dashboard/home
///   4. HARD_LOCK (Tarea 14.2)  → /locked (solo deja pasar /subscription)
///   5. /admin sin `saas.manage` → /dashboard/home
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
      final subscriptionStatus = ref.read(subscriptionStatusProvider);
      final isFounder = ref.read(isFounderProvider);
      final location = routerState.matchedLocation;

      // ── Diagnóstico interno: exento del flujo de auth/onboarding ──────
      if (location == AppRoutes.dictationDiagnostic) {
        return null;
      }

      // ── Vitrina pública: la abre un cliente sin cuenta (RF-23) ────────
      if (location.startsWith('/tienda/')) {
        return null;
      }

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
        return AppRoutes.home;
      }

      // ── Bloqueo total por morosidad (Constitución Art. VI §6.3) ───────
      // Solo la pantalla de bloqueo y "Mi suscripción" siguen accesibles;
      // al volver a ACTIVE el redirect se libera solo (refreshListenable).
      final isHardLocked = subscriptionStatus == SubscriptionStatus.hardLock;
      if (isHardLocked) {
        final allowed =
            location == AppRoutes.locked || location == AppRoutes.subscription;
        return allowed ? null : AppRoutes.locked;
      }
      if (location == AppRoutes.locked) {
        return AppRoutes.home;
      }

      // ── Panel de fundadores: solo con `saas.manage` (D7) ──────────────
      if (location == AppRoutes.founderAdmin && !isFounder) {
        return AppRoutes.home;
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

      // ── Diagnóstico interno — prototipo CRF dictado (Fase 3) ──────────
      GoRoute(
        path: AppRoutes.dictationDiagnostic,
        name: 'dictation-diagnostic',
        builder: (_, __) => const DictationDiagnosticScreen(),
      ),

      // ── Mi cuenta: índice y sub-páginas de lo mío ────────────────────
      GoRoute(
        path: AppRoutes.account,
        name: 'account',
        builder: (_, __) => const AccountScreen(),
        routes: [
          GoRoute(
            path: 'datos',
            name: 'account-data',
            builder: (_, __) => const PersonalDataScreen(),
          ),
          GoRoute(
            path: 'contrasena',
            name: 'account-password',
            builder: (_, __) => const PasswordScreen(),
          ),
          GoRoute(
            path: 'almacen',
            name: 'account-warehouse',
            builder: (_, __) => const OperatingWarehouseScreen(),
          ),
        ],
      ),

      // ── Kardex de ventas y consulta de ticket (Fase 2) ───────────────
      GoRoute(
        path: AppRoutes.salesHistory,
        name: 'sales-history',
        builder: (_, __) => const SalesKardexScreen(),
        routes: [
          GoRoute(
            path: ':id',
            name: 'sale-detail',
            builder: (_, state) =>
                SaleLookupScreen(saleId: state.pathParameters['id']!),
          ),
        ],
      ),

      // ── Pedidos web del tendero ───────────────────────────────────────
      GoRoute(
        path: AppRoutes.storeOrders,
        name: 'store-orders',
        builder: (_, state) => StoreOrdersScreen(
          initialTab: state.uri.queryParameters['tab'] == 'historial' ? 1 : 0,
        ),
        routes: [
          GoRoute(
            path: ':folio',
            name: 'store-order-detail',
            builder: (_, state) => StoreOrderDetailScreen(
              folio: state.pathParameters['folio']!,
            ),
          ),
        ],
      ),

      // ── Administración del comercio ──────────────────────────────────
      GoRoute(
        path: AppRoutes.manageMembers,
        name: 'manage-members',
        builder: (_, __) => const MembersScreen(),
        routes: [
          GoRoute(
            path: 'permisos',
            name: 'manage-permissions',
            builder: (_, __) => const PermissionsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.preferences,
        name: 'preferences',
        builder: (_, __) => const PreferencesScreen(),
        routes: [
          GoRoute(
            path: 'almacenes',
            name: 'warehouses',
            builder: (_, __) => const WarehousesScreen(),
          ),
          GoRoute(
            path: 'categorias',
            name: 'categories',
            builder: (_, __) => const CategoriesScreen(),
          ),
        ],
      ),

      // ── Suscripción SaaS, panel de fundadores y bloqueo — Tarea 14.2 ──
      GoRoute(
        path: AppRoutes.subscription,
        name: 'subscription',
        builder: (_, __) => const SubscriptionCheckoutScreen(),
      ),
      GoRoute(
        path: AppRoutes.founderAdmin,
        name: 'founder-admin',
        builder: (_, __) => const FounderAdminDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.locked,
        name: 'locked',
        builder: (_, __) => const HardLockScreen(),
      ),

      // ── Vitrina pública del catálogo — Tarea 13.2.1 ───────────────────
      GoRoute(
        path: AppRoutes.publicCatalog,
        name: 'public-catalog',
        builder: (_, state) =>
            PublicCatalogScreen(slug: state.pathParameters['slug']!),
        routes: [
          GoRoute(
            path: 'pedido/:folio',
            name: 'public-order',
            builder: (_, state) => OrderTicketScreen(
              slug: state.pathParameters['slug']!,
              accessKey: state.uri.queryParameters['k'],
              folio: state.pathParameters['folio']!,
            ),
          ),
        ],
      ),

      // ── Dashboard con NavigationBar (ShellRoute) ─────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => DashboardShell(
          navigationShell: navigationShell,
        ),
        branches: [
          // Branch 0 — Inicio: Centro de mando (SR-02 / N-08)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                name: 'home',
                builder: (_, __) => const HomeDashboardScreen(),
                routes: [
                  GoRoute(
                    path: 'notifications',
                    name: 'notifications',
                    builder: (_, __) => const NotificationsScreen(),
                  ),
                ],
              ),
            ],
          ),

          // Branch 1 — Inventario
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

                  // Hub de Compras, Proveedores y CxP — Tarea 11.2
                  GoRoute(
                    path: 'purchases',
                    name: 'purchases',
                    builder: (_, __) => const PurchasesHubScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        name: 'purchase-create',
                        builder: (_, __) => const PurchaseCreateScreen(),
                      ),
                    ],
                  ),

                  // Panel de difusión del catálogo — Tarea 13.2.3
                  GoRoute(
                    path: 'catalog',
                    name: 'catalog-share',
                    builder: (_, __) => const CatalogShareScreen(),
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

          // Branch 2 — Ventas (Tarea 6.2)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.sales,
                name: 'sales',
                builder: (_, __) => const CheckoutScreen(),
              ),
            ],
          ),

          // Branch 3 — Caja (Tarea 9.2)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.cash,
                name: 'cash',
                builder: (_, __) => const CashSessionScreen(),
              ),
            ],
          ),

          // Branch 4 — Reportes: dashboard analítico (Tarea 15.2.3)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.reports,
                name: 'reports',
                builder: (_, __) => const AnalyticsDashboardScreen(),
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
// Listenable compuesto — notifica al router cuando CUALQUIERA de los
// providers que gobiernan el redirect cambia (sesión, onboarding, estado de
// suscripción o perfil de fundador).
// ---------------------------------------------------------------------------

class _CompositeRefreshListenable extends ChangeNotifier {
  _CompositeRefreshListenable(Ref ref) {
    ref.listen(sessionProvider, (_, __) => notifyListeners());
    ref.listen(onboardingCompleteProvider, (_, __) => notifyListeners());
    ref.listen(subscriptionStatusProvider, (_, __) => notifyListeners());
    ref.listen(isFounderProvider, (_, __) => notifyListeners());
  }
}
