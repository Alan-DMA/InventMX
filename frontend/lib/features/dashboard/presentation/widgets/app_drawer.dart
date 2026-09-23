import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../account/presentation/account_provider.dart';
import '../../../auth/presentation/login_provider.dart';
import '../../../inventory/presentation/widgets/clone_catalog_sheet.dart';
import '../../../management/presentation/management_provider.dart';
import '../../../saas_admin/presentation/saas_provider.dart';

/// Menú ☰ del Centro de Mando, con puertas por rol (Permisos por rol, Fase A).
///
/// Tres secciones que siguen la propiedad de cada cosa: **Operación** (lo que
/// se hace en el día, por permiso), **Administración** (lo del negocio: sólo
/// Dueño/Encargado; la sección no existe para quien no tenga nada en ella) y
/// **Sistema** (panel de fundadores, que ningún comercio ve). La cabecera
/// lleva a "Mi perfil": lo propio de cada quien no va en la lista.
///
/// Regla: ocultar, no deshabilitar — nunca se ofrece una entrada cuyo destino
/// el router rebotaría.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(currentMemberProvider).valueOrNull;
    final role = ref.watch(myRoleProvider);
    final userName = member?.name ?? 'Comercio Nexus';
    final userEmail = ref.watch(currentUserNameProvider) ?? '';

    final canCheckout = ref.watch(canCheckoutProvider);
    final canViewSales = ref.watch(canViewSalesProvider);
    final canAdjustStock = ref.watch(canAdjustStockProvider);
    final canViewPurchases = ref.watch(canViewPurchasesProvider);
    final canViewCash = ref.watch(canViewCashProvider);
    final canSeeReports = ref.watch(canSeeReportsProvider);
    final canManageMembers = ref.watch(canManageMembersProvider);
    final canManageStore = ref.watch(canManageStoreProvider);
    final isOwner = ref.watch(isOwnerProvider);
    final canSubscription = ref.watch(canSeeSubscriptionProvider);
    final isCorporativo = ref.watch(isCorporativoPlanProvider);
    final isFounder = ref.watch(isFounderProvider);

    void goTo(String route, {bool replaceTab = false}) {
      Navigator.of(context).pop();
      if (replaceTab) {
        context.go(route);
      } else {
        context.push(route);
      }
    }

    final administration = <Widget>[
      if (canSeeReports)
        _DrawerItem(
          key: const Key('drawerReports'),
          icon: Icons.bar_chart_rounded,
          title: 'Reportes',
          onTap: () => goTo(AppRoutes.reports),
        ),
      if (canManageMembers)
        _DrawerItem(
          key: const Key('drawerMembers'),
          icon: Icons.people_outline_rounded,
          title: 'Usuarios y permisos',
          onTap: () => goTo(AppRoutes.manageMembers),
        ),
      if (canManageStore)
        _DrawerItem(
          key: const Key('drawerPreferences'),
          icon: Icons.tune_rounded,
          title: 'Preferencias operativas',
          onTap: () => goTo(AppRoutes.preferences),
        ),
      if (canSubscription)
        _DrawerItem(
          key: const Key('drawerSubscription'),
          icon: Icons.card_membership_rounded,
          title: 'Mi suscripción',
          onTap: () => goTo(AppRoutes.subscription),
        ),
      // RF-31: Dueño con Plan Corporativo. No se ofrece para luego negar.
      if (isOwner && isCorporativo)
        _DrawerItem(
          key: const Key('drawerClone'),
          icon: Icons.copy_all_rounded,
          title: 'Clonar catálogo',
          onTap: () {
            Navigator.of(context).pop();
            showCloneCatalogSheet(context);
          },
        ),
    ];

    return Drawer(
      backgroundColor: AppColors.darkSlate,
      child: SafeArea(
        child: Column(
          children: [
            // Cabecera: quién soy → Mi perfil
            InkWell(
              key: const Key('drawerProfile'),
              onTap: () => goTo(AppRoutes.account),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          AppColors.emerald.withValues(alpha: 0.15),
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'N',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.emerald,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            role != null
                                ? '${role.label} · $userEmail'
                                : userEmail,
                            key: const Key('drawerRoleLine'),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.onSurfaceMuted),
                  ],
                ),
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  const _DrawerHeaderCategory('OPERACIÓN'),
                  if (canCheckout)
                    _DrawerItem(
                      key: const Key('drawerPos'),
                      icon: Icons.point_of_sale_rounded,
                      title: 'Punto de venta',
                      onTap: () => goTo(AppRoutes.sales, replaceTab: true),
                    ),
                  if (canViewSales) ...[
                    _DrawerItem(
                      key: const Key('drawerSalesHistory'),
                      icon: Icons.receipt_long_rounded,
                      title: 'Kardex de ventas',
                      onTap: () => goTo(AppRoutes.salesHistory),
                    ),
                    _DrawerItem(
                      key: const Key('drawerStoreOrders'),
                      icon: Icons.shopping_bag_outlined,
                      title: 'Pedidos web',
                      onTap: () => goTo(AppRoutes.storeOrders),
                    ),
                  ],
                  _DrawerItem(
                    key: const Key('drawerInventory'),
                    icon: Icons.inventory_2_rounded,
                    title: 'Inventario',
                    onTap: () => goTo(AppRoutes.inventory, replaceTab: true),
                  ),
                  if (canAdjustStock)
                    _DrawerItem(
                      key: const Key('drawerGondola'),
                      icon: Icons.qr_code_scanner_rounded,
                      title: 'Modo góndola',
                      onTap: () => goTo(AppRoutes.gondola),
                    ),
                  if (canViewPurchases)
                    _DrawerItem(
                      key: const Key('drawerPurchases'),
                      icon: Icons.local_shipping_rounded,
                      title: 'Compras y proveedores',
                      onTap: () => goTo(AppRoutes.purchases, replaceTab: true),
                    ),
                  if (canViewCash)
                    _DrawerItem(
                      key: const Key('drawerCash'),
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'Caja y turnos',
                      onTap: () => goTo(AppRoutes.cash, replaceTab: true),
                    ),
                  // Configurar y compartir la vitrina es del negocio (D16).
                  if (canManageStore)
                    _DrawerItem(
                      key: const Key('drawerCatalog'),
                      icon: Icons.storefront_rounded,
                      title: 'Catálogo web / WhatsApp',
                      onTap: () => goTo(AppRoutes.catalogShare),
                    ),
                  if (administration.isNotEmpty) ...[
                    const Divider(color: AppColors.border, height: 24),
                    const _DrawerHeaderCategory('ADMINISTRACIÓN'),
                    ...administration,
                  ],
                  // Operar la plataforma no es cosa de ningún comercio.
                  if (isFounder) ...[
                    const Divider(color: AppColors.border, height: 24),
                    const _DrawerHeaderCategory('SISTEMA'),
                    _DrawerItem(
                      key: const Key('drawerFounders'),
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Panel de fundadores',
                      tint: AppColors.skyBlue,
                      onTap: () => goTo(AppRoutes.founderAdmin),
                    ),
                  ],
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: ListTile(
                key: const Key('drawerLogout'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading:
                    const Icon(Icons.logout_rounded, color: AppColors.error),
                title: const Text(
                  'Cerrar sesión',
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await ref.read(loginProvider.notifier).logout();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerHeaderCategory extends StatelessWidget {
  const _DrawerHeaderCategory(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          color: AppColors.onSurfaceMuted,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, size: 20, color: tint ?? AppColors.onSurface),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: tint ?? AppColors.onSurface,
        ),
      ),
      onTap: onTap,
    );
  }
}
