import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../account/presentation/widgets/warehouse_scope_badge.dart';
import '../domain/stock_alert.dart';
import 'dashboard_provider.dart';
import 'widgets/stock_alert_row.dart';

/// Todas las alertas de stock del alcance elegido en la leyenda (D39).
///
/// Antes "Ver todas" llevaba a Inventario filtrado, que sólo ve el almacén
/// donde se opera (D23): viendo "Todos los almacenes" en el Inicio se perdían
/// las alertas de los demás (QA de Eduardo, Sep 27). Aquí se agrupan por
/// almacén y cada una abre la ficha en su almacén (D40).
class StockAlertsScreen extends ConsumerWidget {
  const StockAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dailySnapshotProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const ScopedAppBarTitle(
          switchable: true,
          title: Text(
            'Alertas de stock',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
        ),
      ),
      body: snapshot.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.emerald),
        ),
        error: (_, __) => _Message(
          icon: Icons.cloud_off_rounded,
          text: 'No se pudieron cargar las alertas.',
          action: TextButton(
            onPressed: () => ref.read(dailySnapshotProvider.notifier).refresh(),
            child: const Text('Reintentar'),
          ),
        ),
        data: (data) => data.lowStockAlerts.isEmpty
            ? const _Message(
                icon: Icons.check_circle_outline_rounded,
                text: 'Todo en orden: ningún producto por agotarse.',
              )
            : _GroupedAlerts(alerts: data.lowStockAlerts),
      ),
    );
  }
}

class _GroupedAlerts extends StatelessWidget {
  const _GroupedAlerts({required this.alerts});

  final List<StockAlertItem> alerts;

  @override
  Widget build(BuildContext context) {
    // Por almacén, en el orden en que aparecen (el servidor ya las ordena
    // de más a menos urgente).
    final groups = <String, List<StockAlertItem>>{};
    for (final alert in alerts) {
      groups.putIfAbsent(alert.warehouseName ?? 'Sin almacén', () => []).add(alert);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(
              '${entry.key.toUpperCase()} · ${entry.value.length}',
              key: Key('stockAlertsGroup-${entry.key}'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final alert in entry.value)
                  StockAlertRow(
                    alert: alert,
                    onTap: () => context.push(AppRoutes.alertProductPath(
                      alert.productId,
                      warehouseId: alert.warehouseId,
                      fromList: true,
                    )),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.onSurfaceMuted),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.onSurfaceMuted),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
