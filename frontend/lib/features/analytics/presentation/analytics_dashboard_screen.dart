import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart' show AppRoutes;
import '../../../core/theme/app_colors.dart';
import '../../saas_admin/domain/subscription.dart' show mxn;
import '../../saas_admin/presentation/saas_provider.dart';
import '../domain/analytics_dashboard.dart';
import 'analytics_dashboard_provider.dart';
import 'employee_performance_screen.dart';
import 'widgets/daily_sales_chart.dart';

/// Dashboard analítico — Tarea 15.2.3 (RF-20 rentabilidad real, RF-21
/// dashboard en tiempo real, SR-02 métricas en $ MXN).
///
/// Orden de lectura: cuánto vendí (serie diaria) → cuánto gané (utilidad
/// bruta con costo congelado) → contra el período anterior → qué se vendió.
/// Sin tarjetas iguales de "métrica héroe", sin enmarcado de pérdida: la
/// comparativa muestra ambos montos y el cambio como dato.
///
/// Trazabilidad: Doc. Maestro Sección 5.5 (RF-20, RF-21), Sección 6 (SR-02)
///              Constitución Art. I (1.2.4 MXN) · HU-23 / CU-30
class AnalyticsDashboardScreen extends ConsumerWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(analyticsDashboardProvider);
    final period = ref.watch(dashboardPeriodProvider);
    final today = ref.watch(clockProvider)();
    // Columna acotada a 600 dp en tablet (mismo criterio que Mi suscripción):
    // las cifras no se estiran y los chips van alineados a la misma columna.
    final width = MediaQuery.sizeOf(context).width;
    final side = width > 632 ? (width - 600) / 2 : 16.0;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Reportes',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface),
        ),
        actions: [
          IconButton(
            key: const Key('commissionsButton'),
            tooltip: 'Mis comisiones',
            icon: const Icon(Icons.badge_outlined, color: AppColors.onSurface),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EmployeePerformanceScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Período ────────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(side, 4, side, 8),
              child: Row(
                children: [
                  for (final p in DashboardPeriod.values) ...[
                    _PeriodChip(
                      key: Key('period-${p.name}'),
                      label: p.label,
                      isSelected: p == period,
                      onTap: () => ref.read(dashboardPeriodProvider.notifier).state = p,
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),

            // ── Contenido ─────────────────────────────────────────────────
            Expanded(
              child: dashboardAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.emerald),
                ),
                error: (error, _) => _ErrorState(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(analyticsDashboardProvider),
                ),
                data: (d) => d.isEmpty
                    ? _EmptyState(period: d.period)
                    : RefreshIndicator(
                        color: AppColors.emerald,
                        backgroundColor: AppColors.surface,
                        onRefresh: () async {
                          ref.invalidate(analyticsDashboardProvider);
                          await ref.read(analyticsDashboardProvider.future);
                        },
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(side, 4, side, 24),
                          children: [
                            _SalesSection(dashboard: d, today: today),
                            const SizedBox(height: 12),
                            _ProfitSection(dashboard: d),
                            const SizedBox(height: 12),
                            _ComparisonSection(comparison: d.comparison),
                            const SizedBox(height: 12),
                            _TopProductsSection(products: d.topProducts),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Secciones
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceMuted,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Enlace discreto en el encabezado de una sección — texto + chevron, sin
/// caja: compite lo justo con el título y no con la cifra.
class _SectionLink extends StatelessWidget {
  const _SectionLink({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.skyBlue,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.skyBlue),
            ],
          ),
        ),
      ),
    );
  }
}

const _amountStyle = TextStyle(
  fontSize: 30,
  fontWeight: FontWeight.w800,
  color: AppColors.onSurface,
  height: 1.1,
  fontFeatures: [FontFeature.tabularFigures()],
);

const _subStyle = TextStyle(
  fontSize: 13,
  color: AppColors.onSurfaceMuted,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// Ventas: monto del período, tickets, ticket promedio y la serie diaria.
class _SalesSection extends StatelessWidget {
  const _SalesSection({required this.dashboard, required this.today});
  final AnalyticsDashboard dashboard;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    return _Section(
      title: 'Ventas · ${d.comparison.currentLabel.toLowerCase()}',
      // Puerta al kardex de ventas (Fase 2): del agregado al renglón.
      trailing: _SectionLink(
        key: const Key('salesHistoryLink'),
        label: 'Ver ventas',
        onTap: () => context.push(AppRoutes.salesHistory),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mxn(d.totalRevenueMxn), key: const Key('totalRevenue'), style: _amountStyle),
          const SizedBox(height: 4),
          Text(
            '${d.totalOrders} ${d.totalOrders == 1 ? 'ticket' : 'tickets'} · '
            'ticket promedio ${mxn(d.averageTicketMxn)}',
            style: _subStyle,
          ),
          const SizedBox(height: 16),
          DailySalesChart(points: d.dailySales, today: today),
        ],
      ),
    );
  }
}

/// Ganancia: utilidad bruta con el costo registrado de cada producto (RF-20).
class _ProfitSection extends StatelessWidget {
  const _ProfitSection({required this.dashboard});
  final AnalyticsDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    final negative = d.grossProfitMxn < 0;
    return _Section(
      title: 'Ganancia',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mxn(d.grossProfitMxn),
            key: const Key('grossProfit'),
            style: _amountStyle.copyWith(color: negative ? AppColors.error : AppColors.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            '${d.grossMarginPercent.toStringAsFixed(1)}% de margen sobre ventas',
            style: _subStyle,
          ),
          const SizedBox(height: 8),
          const Text(
            'Utilidad bruta: lo vendido menos el costo que tenía cada producto '
            'al momento de venderse. Los productos sin costo registrado cuentan '
            'como 100% de ganancia.',
            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Comparativa: dos barras, ambos montos, el cambio como dato.
class _ComparisonSection extends StatelessWidget {
  const _ComparisonSection({required this.comparison});
  final PeriodComparison comparison;

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    final change = c.changePercent;
    final maxValue = c.currentRevenueMxn > c.previousRevenueMxn
        ? c.currentRevenueMxn
        : c.previousRevenueMxn;

    final Widget changeChip;
    if (change == null) {
      changeChip = const Text('Sin base de comparación', style: _subStyle);
    } else {
      final up = change >= 0;
      final color = change == 0
          ? AppColors.onSurfaceMuted
          : (up ? AppColors.emerald : AppColors.error);
      changeChip = Text(
        '${up ? '+' : ''}${change.toStringAsFixed(1)}%',
        key: const Key('comparisonChange'),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }

    return _Section(
      title: 'Comparado con ${c.previousLabel.toLowerCase()}',
      trailing: changeChip,
      child: Column(
        children: [
          _HBar(label: c.currentLabel, value: c.currentRevenueMxn, maxValue: maxValue, emphasized: true),
          const SizedBox(height: 10),
          _HBar(label: c.previousLabel, value: c.previousRevenueMxn, maxValue: maxValue, emphasized: false),
        ],
      ),
    );
  }
}

class _HBar extends StatelessWidget {
  const _HBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.emphasized,
  });

  final String label;
  final double value;
  final double maxValue;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
                color: emphasized ? AppColors.onSurface : AppColors.onSurfaceMuted,
              ),
            ),
            Text(
              mxn(value),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: emphasized ? AppColors.onSurface : AppColors.onSurfaceMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(color: AppColors.surfaceVariant),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    color: emphasized
                        ? AppColors.emerald
                        : AppColors.onSurfaceMuted.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Lo más vendido: hasta 5, por ingreso, con unidades y utilidad.
class _TopProductsSection extends StatelessWidget {
  const _TopProductsSection({required this.products});
  final List<TopProduct> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const _Section(
        title: 'Lo más vendido',
        child: Text('Todavía no hay ventas en este período.', style: _subStyle),
      );
    }
    final maxRevenue = products.first.revenueMxn;
    return _Section(
      title: 'Lo más vendido',
      child: Column(
        children: [
          for (var i = 0; i < products.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _TopProductRow(rank: i + 1, product: products[i], maxRevenue: maxRevenue),
          ],
        ],
      ),
    );
  }
}

class _TopProductRow extends StatelessWidget {
  const _TopProductRow({required this.rank, required this.product, required this.maxRevenue});
  final int rank;
  final TopProduct product;
  final double maxRevenue;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final fraction = maxRevenue <= 0 ? 0.0 : (p.revenueMxn / maxRevenue).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurfaceMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${p.unitsSold} ${p.unitsSold == 1 ? 'pza' : 'pzas'} · utilidad ${mxn(p.profitMxn)}',
                    style: _subStyle.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              mxn(p.revenueMxn),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Container(color: AppColors.surfaceVariant),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(color: AppColors.onSurfaceMuted.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chip de período, vacío y error
// ---------------------------------------------------------------------------

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({super.key, required this.label, required this.isSelected, required this.onTap});
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.emerald.withValues(alpha: 0.15) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.emerald : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? AppColors.emerald : AppColors.onSurfaceMuted,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.period});
  final DashboardPeriod period;

  @override
  Widget build(BuildContext context) {
    final when = switch (period) {
      DashboardPeriod.today => 'hoy',
      DashboardPeriod.week => 'esta semana',
      DashboardPeriod.month => 'este mes',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart_rounded, size: 48, color: AppColors.onSurfaceMuted),
            const SizedBox(height: 14),
            Text(
              'Sin ventas $when',
              key: const Key('dashboardEmpty'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.onSurface),
            ),
            const SizedBox(height: 6),
            const Text(
              'En cuanto cobres en Ventas, aquí verás cuánto vendiste y cuánto ganaste.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              key: const Key('dashboardRetry'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(140, 44),
                foregroundColor: AppColors.onSurface,
                side: const BorderSide(color: AppColors.border),
              ),
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
