import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../cases/presentation/widgets/cases_widgets.dart';
import '../../core/admin_colors.dart';
import '../../core/admin_format.dart';
import '../../router/admin_routes.dart';
import '../../session/admin_session.dart';
import '../../tenants/presentation/store_search.dart';
import '../../tenants/presentation/tenant_providers.dart';
import '../domain/today_models.dart';
import 'today_providers.dart';

const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// "martes 30 sep".
String dayLabel(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day}$nbsp${_months[d.month - 1]}';

/// Hoy (etapa 3c, "Feed del día", P15): lo que requiere atención arriba (lo
/// que te toca primero), lo que pasó por día en tu hora, y a un lado los
/// conteos de la plataforma. El buscador abre la ficha de una tienda.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  static const metricsWidth = 280.0;
  static const sideBySideFrom = 980.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth >= sideBySideFrom;
        final main = <Widget>[
          const _Heading(),
          const SizedBox(height: 16),
          const _SearchField(),
          const SizedBox(height: 28),
          ...feed.when(
            skipLoadingOnRefresh: true,
            loading: () => [const CasesSkeleton(rows: 5)],
            error: (e, _) => [
              CasesErrorBlock(message: e.toString(), onRetry: () => ref.invalidate(feedProvider)),
            ],
            data: (state) => [
              _Attention(items: state.attention),
              const SizedBox(height: 32),
              _Days(state: state),
            ],
          ),
          if (!side) ...[const SizedBox(height: 32), const _Metrics()],
        ];
        final column = ListView(
          key: const Key('todayList'),
          padding: EdgeInsets.fromLTRB(side ? 40 : 20, 28, side ? 32 : 20, 48),
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: main),
              ),
            ),
          ],
        );
        if (!side) return column;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: column),
            const VerticalDivider(width: 1, color: AppColors.border),
            const SizedBox(
              width: metricsWidth,
              child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(24, 28, 24, 32), child: _Metrics()),
            ),
          ],
        );
      },
    );
  }
}

class _Heading extends ConsumerWidget {
  const _Heading();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.read(adminClockProvider)();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Semantics(
          header: true,
          child: const Text('Hoy',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
        ),
        const SizedBox(width: 12),
        Text(dayLabel(now), style: const TextStyle(fontSize: 14.5, color: AppColors.onSurfaceMuted)),
      ],
    );
  }
}

/// Un campo que abre el buscador (el mismo de Ctrl K).
class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Buscar tienda, slug o correo del dueño. Atajo: Control K',
        excludeSemantics: true,
        child: Material(
          color: AppColors.darkSlate,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            key: const Key('todaySearch'),
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final picked = await showStoreSearch(context);
              if (picked != null && context.mounted) openStore(context, picked.id);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 20, color: AppColors.onSurfaceMuted),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Buscar tienda, slug o correo del dueño',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted),
                    ),
                  ),
                  SizedBox(width: 10),
                  Text('Ctrl K',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.onSurfaceMuted)),
                ],
              ),
            ),
          ),
        ),
      );
}

// ── Requiere atención ───────────────────────────────────────────────────────

class _Attention extends ConsumerWidget {
  const _Attention({required this.items});
  final List<AttentionItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lo que te toca primero; luego lo más antiguo
    final ordered = [...items]..sort((a, b) {
        if (a.awaitingYou != b.awaitingYou) return a.awaitingYou ? -1 : 1;
        return a.since.compareTo(b.since);
      });
    final now = ref.read(adminClockProvider)();
    return Column(
      key: const Key('todayAttention'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            ordered.isEmpty ? 'Requiere atención' : 'Requiere atención (${ordered.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface),
          ),
        ),
        const SizedBox(height: 10),
        if (ordered.isEmpty)
          Container(
            key: const Key('todayAllClear'),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_rounded, size: 18, color: AppColors.onSurfaceMuted),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Todo en orden: nada espera una decisión ni seguimiento.',
                      style: TextStyle(fontSize: 14, color: AppColors.onSurface)),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < ordered.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  _AttentionRow(item: ordered[i], now: now),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item, required this.now});
  final AttentionItem item;
  final DateTime now;

  (IconData, Color) get _look => switch (item.kind) {
        'CASE_WAITING' => (Icons.forum_outlined, AppColors.onSurfaceMuted),
        'DELETION_PENDING' => (Icons.delete_outline_rounded, AppColors.error),
        'EXPORT_FAILED' => (Icons.error_outline_rounded, AppColors.error),
        'EXPORT_IN_PROGRESS' => (Icons.download_rounded, AppColors.skyBlue),
        'SUPPORT_ACCESS_ACTIVE' => (Icons.visibility_outlined, AppColors.skyBlue),
        'ASSISTED_CODE_UNUSED' => (Icons.key_outlined, AppColors.skyBlue),
        'ABUSE_SUSPENSION' => (Icons.block_rounded, AppColors.error),
        _ => (Icons.info_outline_rounded, AppColors.onSurfaceMuted),
      };

  void _open(BuildContext context) {
    if (item.kind == 'CASE_WAITING' && item.refId != null) {
      context.go(AdminRoutes.casePath(item.refId!));
    } else if (item.tenantId != null) {
      openStore(context, item.tenantId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _look;
    final when = item.until != null
        ? 'hasta ${adminMoment(item.until!)}'
        : 'desde hace ${adminSpan(now.difference(item.since))}';
    final canOpen = (item.kind == 'CASE_WAITING' && item.refId != null) || item.tenantId != null;
    // Ámbar = vence: un caso que lleva más de un día esperando
    final overdue = item.kind == 'CASE_WAITING' && now.difference(item.since) >= const Duration(hours: 24);
    return InkWell(
      key: Key('todayAttention_${item.kind}_${item.refId ?? item.tenantId ?? item.tenantName}'),
      onTap: canOpen ? () => _open(context) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.summary, style: const TextStyle(fontSize: 14, color: AppColors.onSurface, height: 1.35)),
                  const SizedBox(height: 3),
                  Text('${item.tenantName} · $when',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: overdue ? AdminColors.amber : AppColors.onSurfaceMuted,
                        fontWeight: overdue ? FontWeight.w600 : FontWeight.w400,
                      )),
                ],
              ),
            ),
            if (item.awaitingYou) ...[
              const SizedBox(width: 10),
              Container(
                key: const Key('todayAwaitingYou'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(999)),
                child: const Text(
                  'Te toca',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                ),
              ),
            ],
            if (canOpen) const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceMuted),
          ],
        ),
      ),
    );
  }
}

// ── Lo que pasó, por día ────────────────────────────────────────────────────

class _Days extends ConsumerWidget {
  const _Days({required this.state});
  final FeedState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.read(adminClockProvider)();
    final today = localDayStart(now);
    final yesterday = localDayStart(now, daysBack: 1);

    // Agrupar en la hora del equipo (S-12)
    final byDay = <DateTime, List<FeedEvent>>{};
    for (final e in state.events) {
      final day = localDayStart(e.occurredAt.toLocal());
      byDay.putIfAbsent(day, () => []).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    if (!byDay.containsKey(today)) days.insert(0, today);

    String title(DateTime d) => d == today
        ? 'Hoy · ${dayLabel(d)}'
        : d == yesterday
            ? 'Ayer · ${dayLabel(d)}'
            : dayLabel(d)[0].toUpperCase() + dayLabel(d).substring(1);

    return Column(
      key: const Key('todayDays'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in days) ...[
          Semantics(
            header: true,
            child: Text(
              title(day),
              key: Key('todayDay_${day.year}-${day.month}-${day.day}'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onSurface),
            ),
          ),
          const SizedBox(height: 8),
          if (byDay[day] == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: Text('Sin movimientos hoy.', style: TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted)),
            )
          else ...[
            for (final e in byDay[day]!) _EventRow(event: e),
            const SizedBox(height: 16),
          ],
        ],
        if (state.lastEmptyRange != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Sin movimientos del ${dayLabel(state.lastEmptyRange!.$1)} al '
              '${dayLabel(state.lastEmptyRange!.$2.subtract(const Duration(days: 1)))}.',
              key: const Key('todayEmptyRange'),
              style: const TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted),
            ),
          ),
        if (state.earlierError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(state.earlierError!, style: const TextStyle(fontSize: 13, color: AppColors.error)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            key: const Key('todayEarlier'),
            onPressed: state.loadingEarlier ? null : () => ref.read(feedProvider.notifier).loadEarlier(),
            child: Text(state.loadingEarlier ? 'Cargando…' : 'Ver días anteriores'),
          ),
        ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final FeedEvent event;

  @override
  Widget build(BuildContext context) {
    final t = event.occurredAt.toLocal();
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.onSurfaceMuted,
                fontFeatures: [FontFeature.tabularFigures()],
                height: 1.45,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.summary, style: const TextStyle(fontSize: 14, color: AppColors.onSurface, height: 1.4)),
                if ((event.reason ?? '').isNotEmpty)
                  Text(
                    '"${event.reason}"',
                    style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (event.tenantId == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => openStore(context, event.tenantId!),
      child: content,
    );
  }
}

// ── Columna de conteos ──────────────────────────────────────────────────────

class _Metrics extends ConsumerWidget {
  const _Metrics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(metricsProvider);
    return metrics.when(
      skipLoadingOnRefresh: true,
      loading: () => const CasesSkeleton(rows: 3),
      error: (e, _) => CasesErrorBlock(message: e.toString(), onRetry: () => ref.invalidate(metricsProvider)),
      data: (m) => Column(
        key: const Key('todayMetrics'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _MetricTitle('Tiendas'),
          _Metric('Total', m.tenantsTotal, strong: true),
          _Metric('Activas', m.byStatus['ACTIVE'] ?? 0),
          _Metric('Sólo lectura', m.byStatus['SOFT_LOCK'] ?? 0),
          _Metric('Bloqueadas', m.byStatus['HARD_LOCK'] ?? 0),
          _Metric('Suspendidas por soporte', m.abuseSuspended, indent: true),
          const SizedBox(height: 20),
          const _MetricTitle('Planes'),
          _Metric('Emprendedor', m.byPlan['EMPRENDEDOR'] ?? 0),
          _Metric('Comercio', m.byPlan['COMERCIO'] ?? 0),
          _Metric('Corporativo', m.byPlan['CORPORATIVO'] ?? 0),
          const SizedBox(height: 20),
          _Metric('Altas en 30 días', m.signupsLast30Days, strong: true),
          const SizedBox(height: 20),
          const _MetricTitle('Ingreso mensual'),
          Text(
            m.revenueConnected && m.monthlyRevenueMxn != null
                ? '\$${m.monthlyRevenueMxn!.toStringAsFixed(2)} MXN'
                : 'Sin conectar a Google Play aún',
            key: const Key('todayRevenue'),
            style: const TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MetricTitle extends StatelessWidget {
  const _MetricTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          header: true,
          child:
              Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.strong = false, this.indent = false});
  final String label;
  final int value;
  final bool strong;
  final bool indent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: 6, left: indent ? 12 : 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13.5, color: strong ? AppColors.onSurface : AppColors.onSurfaceMuted),
              ),
            ),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 14,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}
