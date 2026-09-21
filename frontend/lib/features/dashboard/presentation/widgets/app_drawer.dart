import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../account/presentation/account_provider.dart';
import '../../../auth/presentation/login_provider.dart';
import '../../../management/presentation/management_provider.dart';

/// Menú lateral (Drawer) de navegación principal accesible desde el icono
/// hamburguesa del AppBar del Centro de Mando.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(currentMemberProvider).valueOrNull;
    final userName = member?.name ?? 'Comercio Nexus';
    final userEmail = ref.watch(currentUserNameProvider) ?? '';

    return Drawer(
      backgroundColor: AppColors.darkSlate,
      child: SafeArea(
        child: Column(
          children: [
            // Encabezado de perfil del comercio y usuario
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.emerald.withValues(alpha: 0.15),
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
                          userEmail,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Lista de accesos de navegación
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _DrawerHeaderCategory('OPERACIÓN COMERCIAL'),
                  _DrawerItem(
                    icon: Icons.point_of_sale_rounded,
                    title: 'Punto de Venta (POS)',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(AppRoutes.sales);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.receipt_long_rounded,
                    title: 'Kardex de Ventas',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.salesHistory);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.inventory_2_rounded,
                    title: 'Inventario de Mercancía',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(AppRoutes.inventory);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Modo Góndola (Escaneo)',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.gondola);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.local_shipping_rounded,
                    title: 'Compras y Proveedores',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(AppRoutes.purchases);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'Caja y Turnos',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(AppRoutes.cash);
                    },
                  ),

                  const Divider(color: AppColors.border, height: 24),
                  _DrawerHeaderCategory('INTELIGENCIA Y CANALES'),
                  _DrawerItem(
                    icon: Icons.bar_chart_rounded,
                    title: 'Reportes y Analítica',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.reports);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.storefront_rounded,
                    title: 'Catálogo Web / WhatsApp',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.catalogShare);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.shopping_bag_outlined,
                    title: 'Pedidos Web del Catálogo',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.storeOrders);
                    },
                  ),

                  const Divider(color: AppColors.border, height: 24),
                  _DrawerHeaderCategory('CONFIGURACIÓN Y CUENTA'),
                  _DrawerItem(
                    icon: Icons.people_outline_rounded,
                    title: 'Usuarios y Permisos',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.manageMembers);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.card_membership_rounded,
                    title: 'Mi Suscripción SaaS',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.subscription);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.account_circle_outlined,
                    title: 'Mi Perfil y Almacén',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.account);
                    },
                  ),
                ],
              ),
            ),

            // Pie de drawer con botón de cierre de sesión
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: const Icon(Icons.logout_rounded, color: AppColors.error),
                title: const Text(
                  'Cerrar Sesión',
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
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, size: 20, color: AppColors.onSurface),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurface,
        ),
      ),
      onTap: onTap,
    );
  }
}
