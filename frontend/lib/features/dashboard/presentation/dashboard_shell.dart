import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../saas_admin/presentation/subscription_lock_banner.dart';
import '../../whatsapp_catalog/presentation/widgets/new_order_banner.dart';

/// Shell de navegación principal — sustituye al _DashboardPlaceholder.
///
/// Implementa un NavigationBar de 4 tabs usando ShellRoute de GoRouter,
/// lo que garantiza que la barra persiste entre tabs sin reconstruirse.
///
/// Tabs:
///   0 — Inicio      (/dashboard/home)         ← Centro de mando, N-08
///   1 — Inventario  (/dashboard/inventory)
///   2 — Ventas      (/dashboard/sales)        ← CheckoutScreen D6
///   3 — Caja        (/dashboard/cash)         ← Tarea 9.2
///   4 — Reportes    (/dashboard/reports)      ← Tarea 15.2.3
class DashboardShell extends StatelessWidget {
  const DashboardShell({
    super.key,
    required this.navigationShell,
  });

  /// Shell de GoRouter — maneja el stack de navegación de cada tab.
  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    _TabItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Inicio',
    ),
    _TabItem(
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2_rounded,
      label: 'Inventario',
    ),
    _TabItem(
      icon: Icons.point_of_sale_outlined,
      activeIcon: Icons.point_of_sale_rounded,
      label: 'Ventas',
    ),
    _TabItem(
      icon: Icons.local_shipping_outlined,
      activeIcon: Icons.local_shipping_rounded,
      label: 'Compras',
    ),
    _TabItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      label: 'Caja',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      body: Column(
        children: [
          // Solo lectura por morosidad — visible en todas las pestañas (14.2.3)
          const SubscriptionLockBanner(),
          // Pedido web nuevo: se ve en cualquier tab y mantiene vivo el socket.
          const NewOrderBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: _buildNavigationBar(),
    );
  }

  Widget _buildNavigationBar() {
    return NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: _onTabSelected,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.emerald.withValues(alpha: 0.15),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: _tabs
          .map(
            (tab) => NavigationDestination(
              icon: Icon(tab.icon, color: AppColors.onSurfaceMuted),
              selectedIcon: Icon(tab.activeIcon, color: AppColors.emerald),
              label: tab.label,
            ),
          )
          .toList(),
    );
  }

  void _onTabSelected(int index) {
    navigationShell.goBranch(
      index,
      // Vuelve a la raíz del branch si se toca el tab ya activo
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

// ---------------------------------------------------------------------------
// Modelo de tab
// ---------------------------------------------------------------------------

class _TabItem {
  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

// ---------------------------------------------------------------------------
// Placeholders para tabs aún no implementados
// ---------------------------------------------------------------------------

class SalesPlaceholder extends StatelessWidget {
  const SalesPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const _ModulePlaceholder(
        icon: Icons.point_of_sale_rounded,
        title: 'Ventas',
        subtitle: 'Disponible en Día 6',
      );
}

class CashPlaceholder extends StatelessWidget {
  const CashPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const _ModulePlaceholder(
        icon: Icons.account_balance_wallet_rounded,
        title: 'Caja',
        subtitle: 'Disponible en Día 9',
      );
}

class ReportsPlaceholder extends StatelessWidget {
  const ReportsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const _ModulePlaceholder(
        icon: Icons.bar_chart_rounded,
        title: 'Reportes',
        subtitle: 'Disponible en Día 15',
      );
}

class _ModulePlaceholder extends StatelessWidget {
  const _ModulePlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: Text(title),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.onSurfaceMuted),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
