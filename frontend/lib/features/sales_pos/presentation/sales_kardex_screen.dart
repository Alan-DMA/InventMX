import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart' show AppRoutes;
import '../../../core/theme/app_colors.dart';
import '../../saas_admin/domain/subscription.dart' show mxn, shortDate;
import '../../saas_admin/presentation/saas_provider.dart' show clockProvider;
import '../domain/sale_summary.dart';
import 'sales_kardex_provider.dart';

/// Kardex de ventas — Fase 2 (plan de cuenta + Dashboard, Sep 2026).
///
/// Hermano del kardex de inventario (`KardexBottomSheet`, 4.2.B): misma
/// anatomía — encabezado con embudo, panel de filtros colapsable, lista con
/// scroll infinito, skeleton, vacío y error — pero como **página**, porque
/// de aquí se entra al detalle y se vuelve.
///
/// Dos tareas reales detrás del mostrador gobiernan la jerarquía del renglón:
/// el cajero busca "la de hace cinco minutos" (hora y total mandan; el folio
/// es secundario) y el dueño filtra por cajero o forma de pago y necesita
/// ver cuántas y cuánto suman (resumen del recorte bajo los filtros).
///
/// Trazabilidad: Doc. Maestro RF-08 (nota de venta) · docs/api/sales.yaml
///              `GET /sales`, `GET /sales/{id}` (pendientes de Alan, 8.1).
class SalesKardexScreen extends ConsumerStatefulWidget {
  const SalesKardexScreen({super.key});

  @override
  ConsumerState<SalesKardexScreen> createState() => _SalesKardexScreenState();
}

class _SalesKardexScreenState extends ConsumerState<SalesKardexScreen> {
  final _scrollController = ScrollController();
  bool _filtersVisible = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent * 0.8) {
      ref.read(salesKardexProvider.notifier).loadMore();
    }
  }

  // ── Selectores de fecha ────────────────────────────────────────────────

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.emerald,
            onPrimary: AppColors.darkSlate,
            surface: AppColors.surface,
            onSurface: AppColors.onSurface,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) onPicked(picked);
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(salesKardexProvider);
    // Columna acotada a 600 dp en tablet, como Reportes.
    final width = MediaQuery.sizeOf(context).width;
    final side = width > 632 ? (width - 600) / 2 : 0.0;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Historial de ventas',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        // Punto sobre el embudo (mismo patrón que la campana de Avisos) en
        // vez de un pill de texto: con la fuente real, "Historial de
        // ventas" + "Filtros activos" no cabían en 384 dp — visible sólo en
        // dispositivo, no en las capturas de /impeccable (fuente sustituta).
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                key: const Key('salesFiltersButton'),
                tooltip: 'Filtros',
                onPressed: () =>
                    setState(() => _filtersVisible = !_filtersVisible),
                icon: Icon(
                  Icons.filter_list_rounded,
                  size: 22,
                  color: _filtersVisible || state.hasActiveFilters
                      ? AppColors.emerald
                      : AppColors.onSurfaceMuted,
                ),
              ),
              if (state.hasActiveFilters)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    key: const Key('activeFiltersBadge'),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.emerald,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: _filtersVisible
                  ? _FiltersPanel(
                      state: state,
                      side: side,
                      onPickFrom: () => _pickDate(
                        current: state.query.dateFrom,
                        onPicked: (d) => ref
                            .read(salesKardexProvider.notifier)
                            .setDateFrom(d),
                      ),
                      onPickTo: () => _pickDate(
                        current: state.query.dateTo,
                        onPicked: (d) =>
                            ref.read(salesKardexProvider.notifier).setDateTo(d),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            _SummaryStrip(state: state, side: side),
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: _buildBody(state, side)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(SalesKardexState state, double side) {
    if (state.isLoading) return const _Skeleton();
    if (state.hasError) {
      return _ErrorState(
        onRetry: () => ref.read(salesKardexProvider.notifier).retry(),
      );
    }
    if (!state.hasSales) {
      return _EmptyState(
        hasFilters: state.hasActiveFilters,
        onClearFilters: () =>
            ref.read(salesKardexProvider.notifier).clearFilters(),
        onGoSell: () => context.go(AppRoutes.sales),
      );
    }
    return _buildList(state, side);
  }

  // ── Lista con separadores de día ───────────────────────────────────────

  Widget _buildList(SalesKardexState state, double side) {
    final today = ref.watch(clockProvider)();
    final rows = _groupByDay(state.sales, today);

    return RefreshIndicator(
      color: AppColors.emerald,
      backgroundColor: AppColors.surface,
      onRefresh: () => ref.read(salesKardexProvider.notifier).refresh(),
      child: ListView.builder(
        key: const PageStorageKey('salesKardexList'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(side, 0, side, 32),
        itemCount: rows.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (ctx, index) {
          if (index == rows.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.emerald,
                  ),
                ),
              ),
            );
          }
          final row = rows[index];
          if (row is _DayHeader) return _DayHeaderTile(label: row.label);
          final sale = (row as _SaleRow).sale;
          return _SaleTile(
            sale: sale,
            onTap: () => context.push(AppRoutes.saleDetailPath(sale.id)),
          );
        },
      ),
    );
  }

  /// Intercala un encabezado cada vez que cambia el día. La lista ya viene
  /// ordenada de más reciente a más antigua.
  static List<_ListRow> _groupByDay(List<SaleSummary> sales, DateTime today) {
    final rows = <_ListRow>[];
    DateTime? currentDay;
    for (final s in sales) {
      final day =
          DateTime(s.completedAt.year, s.completedAt.month, s.completedAt.day);
      if (day != currentDay) {
        currentDay = day;
        rows.add(_DayHeader(_dayLabel(day, today)));
      }
      rows.add(_SaleRow(s));
    }
    return rows;
  }

  static String _dayLabel(DateTime day, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    final weekday = _weekdays[day.weekday - 1];
    final date = day.year == today.year
        ? shortDate(day)
        : '${shortDate(day)} ${day.year}';
    return '$weekday $date';
  }
}

const _weekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo'
];

sealed class _ListRow {
  const _ListRow();
}

class _DayHeader extends _ListRow {
  const _DayHeader(this.label);
  final String label;
}

class _SaleRow extends _ListRow {
  const _SaleRow(this.sale);
  final SaleSummary sale;
}

// ---------------------------------------------------------------------------
// Resumen del recorte — "N ventas · $X"
// ---------------------------------------------------------------------------

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.state, required this.side});
  final SalesKardexState state;
  final double side;

  @override
  Widget build(BuildContext context) {
    // Sin datos aún (skeleton/error) no hay nada que resumir: la franja
    // conserva su alto para que la lista no salte al aparecer.
    final ready = !state.isLoading && !state.hasError;
    final count = state.total;
    final label = count == 1 ? '1 venta' : '$count ventas';
    // Con devoluciones, el neto no coincide con la suma de los renglones:
    // se muestra la cuenta completa (QA de Eduardo, Sep 21) para que
    // Reportes y el historial cuadren a simple vista.
    final refunded = state.refundedAmountMxn;
    final hasRefunds = refunded > 0;
    final gross = state.totalAmountMxn + refunded;

    return SizedBox(
      height: hasRefunds ? 56 : 36,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16 + side),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: ready ? 1 : 0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    key: const Key('salesSummaryCount'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceMuted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    mxn(state.totalAmountMxn),
                    key: const Key('salesSummaryAmount'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              if (hasRefunds) ...[
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${mxn(gross)} vendidos − ${mxn(refunded)} devueltos',
                    key: const Key('salesSummaryRefunds'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceMuted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panel de filtros
// ---------------------------------------------------------------------------

class _FiltersPanel extends ConsumerWidget {
  const _FiltersPanel({
    required this.state,
    required this.side,
    required this.onPickFrom,
    required this.onPickTo,
  });

  final SalesKardexState state;

  /// Margen extra en tablet: el fondo del panel cruza todo el ancho y el
  /// contenido se queda en la columna de 600 dp.
  final double side;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(salesKardexProvider.notifier);
    final q = state.query;

    return Container(
      padding: EdgeInsets.fromLTRB(16 + side, 8, 16 + side, 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _FilterField(
                  label: 'Desde',
                  child: _DateBox(
                    value: q.dateFrom,
                    hint: 'Cualquier fecha',
                    onTap: onPickFrom,
                    onClear: () => notifier.setDateFrom(null),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FilterField(
                  label: 'Hasta',
                  child: _DateBox(
                    value: q.dateTo,
                    hint: 'Hoy',
                    onTap: onPickTo,
                    onClear: () => notifier.setDateTo(null),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _FilterField(
                  label: 'Pago',
                  child: _Dropdown<SalePaymentKind>(
                    key: const Key('paymentKindFilter'),
                    value: q.paymentKind,
                    hint: 'Todas las formas',
                    items: [
                      for (final k in SalePaymentKind.values)
                        DropdownMenuItem(
                          value: k,
                          child: Row(
                            children: [
                              Icon(k.icon, size: 14, color: k.color),
                              const SizedBox(width: 6),
                              Text(k.label,
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                    onChanged: notifier.setPaymentKind,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FilterField(
                  label: 'Cajero',
                  child: _Dropdown<String>(
                    key: const Key('cashierFilter'),
                    value: q.cashierName,
                    hint: 'Todos',
                    items: [
                      for (final c in state.cashiers)
                        DropdownMenuItem(
                          value: c,
                          child: Text(
                            c,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: notifier.setCashier,
                  ),
                ),
              ),
            ],
          ),
          if (state.hasActiveFilters) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              key: const Key('clearSalesFilters'),
              onPressed: notifier.clearFilters,
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: const Text('Limpiar filtros'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurfaceMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    super.key,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final T? value;
  final String hint;
  final List<DropdownMenuItem<T?>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          style: const TextStyle(fontSize: 12, color: AppColors.onSurface),
          hint: Text(
            hint,
            style:
                const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
          ),
          icon: const Icon(
            Icons.expand_more_rounded,
            size: 16,
            color: AppColors.onSurfaceMuted,
          ),
          items: [
            // Con valor nulo el botón pinta este ítem, no `hint`: se le da el
            // mismo tono apagado que a las fechas sin elegir.
            DropdownMenuItem<T?>(
              value: null,
              child: Text(
                hint,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.onSurfaceMuted),
              ),
            ),
            ...items,
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({
    required this.value,
    required this.hint,
    required this.onTap,
    required this.onClear,
  });

  final DateTime? value;
  final String hint;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final label = v != null
        ? '${v.day.toString().padLeft(2, '0')}/'
            '${v.month.toString().padLeft(2, '0')}/${v.year}'
        : hint;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: v != null
                      ? AppColors.onSurface
                      : AppColors.onSurfaceMuted,
                ),
              ),
            ),
            if (v != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: AppColors.onSurfaceMuted,
                ),
              )
            else
              const Icon(
                Icons.calendar_today_rounded,
                size: 13,
                color: AppColors.onSurfaceMuted,
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Encabezado de día
// ---------------------------------------------------------------------------

class _DayHeaderTile extends StatelessWidget {
  const _DayHeaderTile({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurfaceMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Renglón de venta
// ---------------------------------------------------------------------------

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale, required this.onTap});

  final SaleSummary sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = sale.paymentKind;
    final t = sale.completedAt;
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final pieces = sale.itemCount == 1 ? '1 pza' : '${sale.itemCount} pzas';

    // Reembolso total: se atenúa (sigue en la lista — transparencia, no se
    // oculta) y el total lleva tachado, no se descuenta aquí (es el hecho
    // histórico; lo neto vive en la franja de resumen y en Reportes).
    // Reembolso parcial: la etiqueta dice cuánto volvió y el monto no se
    // tacha — la venta sigue viva por el resto.
    final fully = sale.isFullyRefunded;
    return Opacity(
      opacity: fully ? 0.55 : 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('saleRow-${sale.id}'),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kind.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(kind.icon, size: 18, color: kind.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            time,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (sale.isRefunded) ...[
                            const SizedBox(width: 6),
                            // Flexible: "Devolución −$1,234.00" no debe
                            // empujar el monto fuera del renglón.
                            Flexible(child: _RefundedTag(sale: sale)),
                          ],
                          const Spacer(),
                          Text(
                            mxn(sale.totalMxn),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              decoration:
                                  fully ? TextDecoration.lineThrough : null,
                              decorationColor: AppColors.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${kind.label} · ${sale.cashierName}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.onSurfaceMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            sale.folio,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.onSurfaceMuted,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            pieces,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.onSurfaceMuted,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.onSurfaceMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Reembolsada" cuando volvió todo; "Devolución −$X" cuando fue parcial —
/// la diferencia importa: una venta parcialmente devuelta sigue contando.
class _RefundedTag extends StatelessWidget {
  const _RefundedTag({required this.sale});
  final SaleSummary sale;

  @override
  Widget build(BuildContext context) {
    final text = sale.isFullyRefunded
        ? 'Reembolsada'
        : 'Devolución −${mxn(sale.refundedAmountMxn)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        key: const Key('refundTag'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: AppColors.error,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estados: skeleton · vacío · error
// ---------------------------------------------------------------------------

class _Skeleton extends StatefulWidget {
  const _Skeleton();

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.9).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: _box(11, 40),
          ),
          for (var i = 0; i < 6; i++) _row(),
        ],
      ),
    );
  }

  Widget _row() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            _box(36, 36, radius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [_box(14, 44), const Spacer(), _box(15, 64)]),
                  const SizedBox(height: 6),
                  _box(11, 150),
                  const SizedBox(height: 6),
                  Row(children: [_box(11, 96), const Spacer(), _box(11, 36)]),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _box(double height, double width, {double radius = 5}) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withValues(alpha: _anim.value),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasFilters,
    required this.onClearFilters,
    required this.onGoSell,
  });

  final bool hasFilters;
  final VoidCallback onClearFilters;
  final VoidCallback onGoSell;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilters
                  ? Icons.filter_list_off_rounded
                  : Icons.receipt_long_outlined,
              size: 48,
              color: AppColors.onSurfaceMuted,
            ),
            const SizedBox(height: 12),
            Text(
              hasFilters
                  ? 'Sin ventas con\nestos filtros'
                  : 'Aún no hay ventas\nregistradas',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurfaceMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            if (hasFilters)
              TextButton.icon(
                key: const Key('emptyClearFilters'),
                onPressed: onClearFilters,
                icon: const Icon(Icons.clear_all_rounded, size: 16),
                label: const Text('Limpiar filtros'),
                style: TextButton.styleFrom(foregroundColor: AppColors.emerald),
              )
            else
              ElevatedButton.icon(
                key: const Key('emptyGoSell'),
                onPressed: onGoSell,
                icon: const Icon(Icons.shopping_cart_rounded, size: 16),
                label: const Text('Ir a vender'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AppColors.onSurfaceMuted),
            const SizedBox(height: 12),
            const Text(
              'No se pudieron cargar\nlas ventas',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurface,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              key: const Key('salesRetry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
