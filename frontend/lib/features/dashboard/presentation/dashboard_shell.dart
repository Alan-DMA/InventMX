import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../management/presentation/management_provider.dart';
import '../../saas_admin/presentation/subscription_lock_banner.dart';
import '../../whatsapp_catalog/presentation/widgets/new_order_banner.dart';

/// Shell de navegación principal.
///
/// NavigationBar sobre el `StatefulShellRoute` de GoRouter: la barra persiste
/// entre pestañas sin reconstruirse. Las **ramas** son fijas (5, en el orden
/// de [ShellTab]); las **pestañas visibles** dependen del rol
/// (`visibleTabsProvider`, Permisos por rol Fase A): Cajero sin Compras,
/// Almacenista sin Ventas ni Caja. Por eso el índice de la barra se traduce
/// a índice de rama y viceversa.
///
/// Ramas:
///   0 — Inicio      (/dashboard/home)         ← Centro de mando, N-08
///   1 — Inventario  (/dashboard/inventory)
///   2 — Ventas      (/dashboard/sales)        ← CheckoutScreen D6
///   3 — Compras     (/dashboard/inventory/purchases)
///   4 — Caja        (/dashboard/cash)         ← Tarea 9.2
class DashboardShell extends ConsumerWidget {
  const DashboardShell({
    super.key,
    required this.navigationShell,
  });

  /// Shell de GoRouter — maneja el stack de navegación de cada tab.
  final StatefulNavigationShell navigationShell;

  static const _tabs = <ShellTab, _TabItem>{
    ShellTab.home: _TabItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Inicio',
    ),
    ShellTab.inventory: _TabItem(
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2_rounded,
      label: 'Inventario',
    ),
    ShellTab.sales: _TabItem(
      icon: Icons.point_of_sale_outlined,
      activeIcon: Icons.point_of_sale_rounded,
      label: 'Ventas',
    ),
    ShellTab.purchases: _TabItem(
      icon: Icons.local_shipping_outlined,
      activeIcon: Icons.local_shipping_rounded,
      label: 'Compras',
    ),
    ShellTab.cash: _TabItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      label: 'Caja',
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(visibleTabsProvider);
    final canViewSales = ref.watch(canViewSalesProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      body: Column(
        children: [
          // Solo lectura por morosidad — visible en todas las pestañas (14.2.3)
          const SubscriptionLockBanner(),
          // Pedido web nuevo: se ve en cualquier tab y mantiene vivo el socket.
          // Sólo para quien puede atenderlo (sales.view): montarlo abre el
          // WebSocket, y a un almacenista el servidor se lo rechazaría.
          if (canViewSales) const NewOrderBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: _buildNavigationBar(visible),
    );
  }

  Widget _buildNavigationBar(List<ShellTab> visible) {
    final current = ShellTab.values[navigationShell.currentIndex];
    // Si el rol no ve la rama activa (deep link, o permisos aún cargando),
    // la barra no resalta nada en vez de resaltar una pestaña ajena.
    final selected = visible.indexOf(current);

    return NavigationBar(
      selectedIndex: selected < 0 ? 0 : selected,
      onDestinationSelected: (i) => _onTabSelected(visible[i]),
      backgroundColor: AppColors.surface,
      indicatorColor: selected < 0
          ? Colors.transparent
          : AppColors.emerald.withValues(alpha: 0.15),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        for (final tab in visible)
          NavigationDestination(
            key: Key('shellTab-${tab.name}'),
            icon: Icon(_tabs[tab]!.icon, color: AppColors.onSurfaceMuted),
            selectedIcon: Icon(_tabs[tab]!.activeIcon,
                color: selected < 0
                    ? AppColors.onSurfaceMuted
                    : AppColors.emerald),
            label: _tabs[tab]!.label,
          ),
      ],
    );
  }

  void _onTabSelected(ShellTab tab) {
    navigationShell.goBranch(
      tab.index,
      // Vuelve a la raíz del branch si se toca el tab ya activo
      initialLocation: tab.index == navigationShell.currentIndex,
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
