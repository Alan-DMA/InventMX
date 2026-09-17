import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../account/presentation/account_provider.dart';
import '../../inventory/presentation/inventory_provider.dart';
import '../../inventory/presentation/widgets/add_product_modal.dart';
import '../../management/presentation/management_provider.dart';
import '../../sales_pos/domain/sale_summary.dart';
import '../../saas_admin/presentation/saas_provider.dart' show clockProvider;
// `mxn()` ya existe aquí; se reusa en vez de escribir un tercer formateador.
import '../../saas_admin/domain/subscription.dart' show mxn;
import '../domain/daily_snapshot.dart';
import '../domain/stock_alert.dart';
import 'dashboard_provider.dart';
import 'widgets/quick_stock_adjust_sheet.dart';

/// Centro de mando (SR-02 / N-08) — la pantalla de entrada.
///
/// Fase 3: saludo con contexto (quién, cuándo, dónde), **alertas de stock en
/// línea con presencia completa** (mandan sobre el resto — decisión de
/// Eduardo) y ventas del día condensadas junto al margen. El análisis
/// histórico sigue siendo Reportes (15.2.3).
class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dailySnapshotProvider);
    final unread = ref.watch(unreadNotificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        automaticallyImplyLeading: false,
        actions: [
          _NotificationsBell(unread: unread),
          IconButton(
            key: const Key('homeAccountButton'),
            onPressed: () => context.push(AppRoutes.account),
            icon: const Icon(Icons.account_circle_outlined,
                color: AppColors.onSurface),
            tooltip: 'Mi cuenta',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.emerald,
        backgroundColor: AppColors.surface,
        onRefresh: () => ref.read(dailySnapshotProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const _GreetingHeader(),
            const SizedBox(height: 4),
            const _ContextLine(),
            const SizedBox(height: 22),
            const _SectionLabel('Acciones rápidas'),
            const SizedBox(height: 10),
            const _QuickActions(),
            const SizedBox(height: 26),
            const _SectionLabel('Alertas'),
            const SizedBox(height: 10),
            snapshot.when(
              loading: () => const _SectionSkeleton(),
              error: (e, _) => _SectionError(e),
              data: (data) => _AlertsSection(snapshot: data),
            ),
            const SizedBox(height: 26),
            const _SectionLabel('Cómo va el día'),
            const SizedBox(height: 10),
            snapshot.when(
              loading: () => const _SectionSkeleton(),
              error: (e, _) => _SectionError(e),
              data: (data) => _DaySummary(snapshot: data),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saludo y contexto (fecha · almacén operativo)
// ---------------------------------------------------------------------------

String _firstName(String? fullName) {
  if (fullName == null || fullName.trim().isEmpty) return '';
  return fullName.trim().split(RegExp(r'\s+')).first;
}

String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Buenos días';
  if (h < 19) return 'Buenas tardes';
  return 'Buenas noches';
}

const _weekdays = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];
const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String _longDate(DateTime d) {
  final weekday = _weekdays[d.weekday - 1];
  final capitalized = weekday[0].toUpperCase() + weekday.substring(1);
  return '$capitalized ${d.day} de ${_months[d.month - 1]}';
}

class _GreetingHeader extends ConsumerWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(currentMemberProvider).valueOrNull;
    final firstName = _firstName(member?.name);
    final greeting = _greeting(ref.watch(clockProvider)());

    return Text(
      firstName.isEmpty ? greeting : '$greeting, $firstName',
      key: const Key('homeGreeting'),
      style: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
      ),
    );
  }
}

class _ContextLine extends ConsumerWidget {
  const _ContextLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final warehouse = ref.watch(operatingWarehouseProvider).valueOrNull;

    final text = warehouse == null
        ? _longDate(now)
        : '${_longDate(now)} · ${warehouse.name}';

    return Text(
      text,
      key: const Key('homeContextLine'),
      style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
    );
  }
}

// ---------------------------------------------------------------------------
// Campana
// ---------------------------------------------------------------------------

class _NotificationsBell extends StatelessWidget {
  const _NotificationsBell({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          key: const Key('homeNotificationsButton'),
          onPressed: () => context.push(AppRoutes.notifications),
          icon: const Icon(Icons.notifications_none_rounded,
              color: AppColors.onSurface),
          tooltip: 'Avisos',
        ),
        if (unread > 0)
          Positioned(
            top: 8,
            right: 6,
            child: Container(
              key: const Key('homeNotificationsBadge'),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 17),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Acciones rápidas — pensadas para quien está de pie en el mostrador
// ---------------------------------------------------------------------------

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            itemKey: const Key('homeActionSell'),
            icon: Icons.point_of_sale_rounded,
            label: 'Vender',
            // `go` y no `push`: cambia de pestaña, no apila encima de Inicio.
            onTap: () => context.go(AppRoutes.sales),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionCard(
            itemKey: const Key('homeActionAddProduct'),
            icon: Icons.add_box_outlined,
            label: 'Agregar\nproducto',
            onTap: () => showAddProductModal(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionCard(
            itemKey: const Key('homeActionAdjustStock'),
            icon: Icons.tune_rounded,
            label: 'Ajustar\nstock',
            onTap: () => showQuickStockAdjustSheet(context),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.itemKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Key itemKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: itemKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.emerald, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alertas — presencia completa, mandan sobre el resto (decisión de Eduardo)
// ---------------------------------------------------------------------------

class _AlertsSection extends ConsumerWidget {
  const _AlertsSection({required this.snapshot});

  final DailySnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (snapshot.stockAlertCount == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: AppColors.emerald, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Todo en orden — sin productos por acabarse',
                style: TextStyle(fontSize: 13, color: AppColors.onSurface),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${snapshot.stockAlertCount} producto${snapshot.stockAlertCount == 1 ? '' : 's'} necesitan atención',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('homeAlertsSeeAll'),
                  onPressed: () {
                    ref.read(inventoryProvider.notifier).setLowStock(true);
                    context.go(AppRoutes.inventory);
                  },
                  child: const Text('Ver todas'),
                ),
              ],
            ),
          ),
          for (final alert in snapshot.lowStockAlerts)
            _AlertRow(alert: alert),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final StockAlertItem alert;

  @override
  Widget build(BuildContext context) {
    final tint = alert.isOutOfStock ? AppColors.error : AppColors.warning;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('homeAlertRow-${alert.productId}'),
        onTap: () => context.go(AppRoutes.productDetailPath(alert.productId)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                alert.isOutOfStock
                    ? Icons.remove_shopping_cart_outlined
                    : Icons.inventory_2_outlined,
                size: 16,
                color: tint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  alert.productName,
                  style: const TextStyle(
                      fontSize: 13.5, color: AppColors.onSurface),
                ),
              ),
              Text(
                alert.isOutOfStock ? 'Agotado' : 'Quedan ${alert.availableStock}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Resumen del día
// ---------------------------------------------------------------------------

class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.snapshot});

  final DailySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final delta = snapshot.salesDeltaPercent;

    return Column(
      children: [
        _SalesCard(snapshot: snapshot, delta: delta),
        const SizedBox(height: 10),
        const _RecentSalesSection(),
        const SizedBox(height: 10),
        _MetricCard(
          itemKey: const Key('homePayables'),
          icon: Icons.receipt_long_outlined,
          tint: snapshot.payablesOverdueCount > 0
              ? AppColors.error
              : AppColors.onSurface,
          value: mxn(snapshot.payablesDueMxn),
          label: snapshot.payablesOverdueCount > 0
              ? '${snapshot.payablesOverdueCount} cuenta vencida'
              : 'por pagar a proveedores',
          onTap: () => context.go(AppRoutes.purchases),
        ),
        const SizedBox(height: 10),
        _CashCard(snapshot: snapshot),
      ],
    );
  }
}

class _SalesCard extends StatelessWidget {
  const _SalesCard({required this.snapshot, required this.delta});

  final DailySnapshot snapshot;
  final double? delta;

  @override
  Widget build(BuildContext context) {
    final marginPercent = snapshot.marginTodayPercent;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('homeSalesCard'),
        onTap: () => context.go(AppRoutes.reports),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Vendido hoy',
                style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    mxn(snapshot.salesTodayMxn),
                    key: const Key('homeSalesTodayAmount'),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (delta != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        children: [
                          Icon(
                            delta! >= 0
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            size: 16,
                            color: delta! >= 0
                                ? AppColors.emerald
                                : AppColors.error,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${delta! >= 0 ? '+' : ''}${delta!.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: delta! >= 0
                                  ? AppColors.emerald
                                  : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${snapshot.salesTodayCount} ventas · ayer a esta hora '
                '${mxn(snapshot.salesYesterdayMxn)}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.onSurfaceMuted),
              ),
              const Divider(height: 22, color: AppColors.border),
              Row(
                children: [
                  const Icon(Icons.percent_rounded,
                      size: 15, color: AppColors.onSurfaceMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Margen de hoy: ${mxn(snapshot.marginTodayMxn)}'
                      '${marginPercent != null ? ' (${marginPercent.toStringAsFixed(0)}%)' : ''}',
                      key: const Key('homeMarginToday'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Últimas ventas — condensado; las alertas mandan, esto cede.
// ---------------------------------------------------------------------------

class _RecentSalesSection extends ConsumerWidget {
  const _RecentSalesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(recentSalesProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
            child: Row(
              children: [
                const Text(
                  'Últimas ventas',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const Spacer(),
                TextButton(
                  key: const Key('homeSalesSeeAll'),
                  onPressed: () => context.push(AppRoutes.salesHistory),
                  child: const Text('Ver todo'),
                ),
              ],
            ),
          ),
          sales.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.emerald),
                ),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Text(
                e.toString().replaceFirst('Exception: ', ''),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.onSurfaceMuted),
              ),
            ),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(14, 4, 14, 14),
                    child: Text(
                      'Sin ventas todavía hoy',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.onSurfaceMuted),
                    ),
                  )
                : Column(
                    children: [
                      for (final sale in items) _RecentSaleRow(sale: sale),
                      const SizedBox(height: 4),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecentSaleRow extends StatelessWidget {
  const _RecentSaleRow({required this.sale});

  final SaleSummary sale;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('homeRecentSale-${sale.id}'),
        onTap: () => context.push(AppRoutes.salesHistory),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(sale.paymentKind.icon, size: 15, color: sale.paymentKind.color),
              const SizedBox(width: 10),
              Text(
                _formatTime(sale.completedAt),
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.onSurfaceMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sale.folio,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.onSurfaceMuted),
                ),
              ),
              if (sale.isRefunded)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text(
                    'Reembolsada',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ),
              Text(
                mxn(sale.totalMxn),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Caja
// ---------------------------------------------------------------------------

class _CashCard extends StatelessWidget {
  const _CashCard({required this.snapshot});

  final DailySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final open = snapshot.isCashSessionOpen;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const Key('homeCashCard'),
        onTap: () => context.go(AppRoutes.cash),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(
                open ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                size: 20,
                color: open ? AppColors.emerald : AppColors.onSurfaceMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      open ? 'Turno abierto' : 'Sin turno abierto',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      open
                          ? 'Deberías tener ${mxn(snapshot.cashExpectedMxn)} en caja'
                          : 'Ábrelo antes de empezar a cobrar',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.onSurfaceMuted),
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
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.itemKey,
    required this.icon,
    required this.tint,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final Key itemKey;
  final IconData icon;
  final Color tint;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: itemKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: tint),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: tint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.onSurfaceMuted,
        ),
      );
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: CircularProgressIndicator(color: AppColors.emerald)),
      );
}

class _SectionError extends StatelessWidget {
  const _SectionError(this.error);
  final Object error;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          error.toString().replaceFirst('Exception: ', ''),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.onSurfaceMuted),
        ),
      );
}
