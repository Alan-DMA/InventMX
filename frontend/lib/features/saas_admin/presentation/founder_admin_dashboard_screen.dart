import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../data/saas_repository.dart';
import '../domain/founder_metrics.dart';
import '../domain/subscription.dart';
import 'saas_provider.dart';

/// Panel de fundadores — Tarea 14.2.2 (Constitución Art. V §5.3, Doc. Maestro §4.1).
///
/// Solo para usuarios con `saas.manage` (D7); el router rebota al resto.
/// Tres bloques en el orden en que Alan y Eduardo los usan: (1) cómo va el
/// negocio (MRR, activos, morosos, retención), (2) la bandeja de avisos de
/// pago —lo que hay que hacer hoy—, (3) la lista de comercios con filtros y
/// acciones. Toda acción sobre dinero o acceso ajeno confirma con nombre,
/// código y monto; rechazar exige motivo.
class FounderAdminDashboardScreen extends ConsumerStatefulWidget {
  const FounderAdminDashboardScreen({super.key});

  @override
  ConsumerState<FounderAdminDashboardScreen> createState() =>
      _FounderAdminDashboardScreenState();
}

class _FounderAdminDashboardScreenState
    extends ConsumerState<FounderAdminDashboardScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _busy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(tenantFilterProvider.notifier).state =
          ref.read(tenantFilterProvider).copyWith(query: q);
    });
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(
        content: Text(success),
        behavior: SnackBarBehavior.floating,
      ));
    } on SaasException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('No se pudo completar la acción. Inténtalo de nuevo.'),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(ValidationInboxItem item) async {
    final ok = await _confirm(
      title: 'Aprobar pago',
      body:
          '${item.tenantName} (${item.tenantCode}) · ${mxn(item.invoiceAmountMxn)} MXN\n'
          '${item.validation.method.label} · ref. ${item.validation.reference}\n\n'
          'La factura queda pagada y el comercio activo.',
      action: 'Aprobar',
      key: const Key('confirmApprove'),
    );
    if (!ok) return;
    await _run(
      () => ref
          .read(founderDashboardProvider.notifier)
          .approve(item.validation.id),
      '${item.tenantName} está al corriente.',
    );
  }

  Future<void> _reject(ValidationInboxItem item) async {
    final notes = await _askNotes(item);
    if (notes == null) return;
    await _run(
      () => ref
          .read(founderDashboardProvider.notifier)
          .reject(item.validation.id, notes: notes),
      'Aviso rechazado. ${item.tenantName} verá el motivo.',
    );
  }

  Future<void> _setStatus(TenantSummary t, SubscriptionStatus status) async {
    final verb = switch (status) {
      SubscriptionStatus.active => 'Reactivar',
      SubscriptionStatus.softLock => 'Poner en solo lectura',
      SubscriptionStatus.hardLock => 'Suspender',
    };
    final ok = await _confirm(
      title: '$verb ${t.name}',
      body: 'Código ${t.code} · ${t.plan?.name ?? 'sin plan'}'
          '${t.pendingInvoice == null ? '' : ' · ${mxn(t.pendingInvoice!.amountMxn)} MXN pendientes'}\n\n'
          '${status == SubscriptionStatus.active && t.daysOverdue > 0 ? 'Vuelve a ACTIVE y su vencimiento se corre 7 días.' : 'El comercio pasa a ${status.label}.'}',
      action: verb,
      key: Key('confirmStatus-${status.name}'),
      destructive: status != SubscriptionStatus.active,
    );
    if (!ok) return;
    await _run(
      () => ref.read(founderDashboardProvider.notifier).setStatus(t.id, status),
      '${t.name}: ${status.label}.',
    );
  }

  Future<void> _extend(TenantSummary t) async {
    final ok = await _confirm(
      title: 'Extender plazo 7 días',
      body: '${t.name} (${t.code}). Su factura pendiente vence 7 días después.',
      action: 'Extender',
      key: const Key('confirmExtend'),
    );
    if (!ok) return;
    await _run(
      () => ref.read(founderDashboardProvider.notifier).extendDue(t.id, 7),
      'Plazo extendido para ${t.name}.',
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    required Key key,
    bool destructive = false,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Text(body, style: const TextStyle(height: 1.45)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            key: key,
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  destructive ? AppColors.error : AppColors.emerald,
              foregroundColor:
                  destructive ? AppColors.onSurface : AppColors.darkSlate,
            ),
            child: Text(action),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<String?> _askNotes(ValidationInboxItem item) => showDialog<String>(
        context: context,
        builder: (_) => _RejectNotesDialog(item: item),
      );

  @override
  Widget build(BuildContext context) {
    final dash = ref.watch(founderDashboardProvider);
    final filter = ref.watch(tenantFilterProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        title: const Text(
          'Panel de fundadores',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
            onPressed: () =>
                ref.read(founderDashboardProvider.notifier).refresh(),
          ),
        ],
      ),
      body: dash.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.emerald)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e is SaasException
                      ? e.message
                      : 'No se pudo cargar el panel.',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppColors.onSurface, height: 1.4),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      ref.read(founderDashboardProvider.notifier).refresh(),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
        data: (d) => RefreshIndicator(
          color: AppColors.emerald,
          onRefresh: () =>
              ref.read(founderDashboardProvider.notifier).refresh(),
          // Columna acotada: en tablet una columna de teléfono estirada a 736 dp
          // separa cada valor de su acción.
          child: ListView(
            padding: EdgeInsets.fromLTRB(_gutter(context), 4, _gutter(context),
                32 + MediaQuery.of(context).padding.bottom),
            children: [
              _MetricsBlock(metrics: d.metrics),
              const SizedBox(height: 22),
              _sectionTitle(
                'Pagos por validar',
                trailing: d.inbox.isEmpty ? null : '${d.inbox.length}',
              ),
              const SizedBox(height: 8),
              if (d.inbox.isEmpty)
                const _Card(
                  child: Text(
                    'Sin avisos pendientes. Cuando un comercio toque "Ya pagué", aparece aquí.',
                    key: Key('inboxEmpty'),
                    style:
                        TextStyle(color: AppColors.onSurfaceMuted, height: 1.4),
                  ),
                )
              else
                for (final item in d.inbox) ...[
                  _InboxTile(
                    item: item,
                    busy: _busy,
                    onApprove: () => _approve(item),
                    onReject: () => _reject(item),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 14),
              _sectionTitle('Comercios', trailing: '${d.tenants.length}'),
              const SizedBox(height: 8),
              TextField(
                key: const Key('tenantSearch'),
                controller: _search,
                onChanged: _onSearch,
                style: const TextStyle(color: AppColors.onSurface),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o código',
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.onSurfaceMuted),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _FilterChips(filter: filter),
              const SizedBox(height: 10),
              if (d.tenants.isEmpty)
                const _Card(
                  child: Text(
                    'Ningún comercio coincide con el filtro.',
                    key: Key('tenantsEmpty'),
                    style: TextStyle(color: AppColors.onSurfaceMuted),
                  ),
                )
              else
                for (final t in d.tenants) ...[
                  _TenantTile(
                    tenant: t,
                    busy: _busy,
                    onReactivate: () =>
                        _setStatus(t, SubscriptionStatus.active),
                    onSoftLock: () =>
                        _setStatus(t, SubscriptionStatus.softLock),
                    onHardLock: () =>
                        _setStatus(t, SubscriptionStatus.hardLock),
                    onExtend: () => _extend(t),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      ),
    );
  }

  /// Margen lateral que deja el contenido en ≤ 600 dp centrados.
  static double _gutter(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w > 632 ? (w - 600) / 2 : 16;
  }

  Widget _sectionTitle(String t, {String? trailing}) => Row(
        children: [
          Text(t,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface)),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.skyBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                trailing,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.skyBlue),
              ),
            ),
          ],
        ],
      );
}

// ---------------------------------------------------------------------------
// Métricas — una tabla, no tarjetas iguales: MRR manda, el resto acompaña.
// ---------------------------------------------------------------------------

class _MetricsBlock extends StatelessWidget {
  const _MetricsBlock({required this.metrics});
  final FounderMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ingreso mensual recurrente',
              style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    mxn(m.mrrMxn),
                    key: const Key('mrrValue'),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface,
                      fontFeatures: [FontFeature.tabularFigures()],
                      height: 1.05,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Text('MXN / mes',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted)),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat('Activos', '${m.tenantsActive}', AppColors.emerald,
                  key: const Key('statActive')),
              _stat('Solo lectura', '${m.tenantsSoftLock}', AppColors.warning),
              _stat('Bloqueados', '${m.tenantsHardLock}', AppColors.error),
              _stat('Retención', '${(m.retentionRate * 100).round()}%',
                  AppColors.skyBlue),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${m.tenantsTotal} comercios · ${m.newTenants30d} altas en 30 días · '
            '${m.pendingValidations} pagos por validar',
            style:
                const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color, {Key? key}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              key: key,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.onSurfaceMuted)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Bandeja
// ---------------------------------------------------------------------------

class _InboxTile extends StatelessWidget {
  const _InboxTile({
    required this.item,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final ValidationInboxItem item;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final v = item.validation;
    return _Card(
      key: Key('inbox-${v.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.tenantName} · ${item.tenantCode}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface),
                ),
              ),
              Text(
                mxn(item.invoiceAmountMxn),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${v.method.label} · ref. ${v.reference}'
            '${v.createdAt == null ? '' : ' · ${shortDate(v.createdAt!)}'}'
            ' · factura vence ${shortDate(item.invoiceDueDate)}',
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.onSurfaceMuted, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    key: Key('reject-${v.id}'),
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.onSurface,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Rechazar'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    key: Key('approve-${v.id}'),
                    onPressed: busy ? null : onApprove,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: AppColors.darkSlate,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Aprobar',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Comercios
// ---------------------------------------------------------------------------

class _FilterChips extends ConsumerWidget {
  const _FilterChips({required this.filter});
  final TenantFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void set(TenantFilter f) =>
        ref.read(tenantFilterProvider.notifier).state = f;

    Widget chip(String label, bool selected, VoidCallback onTap, {Key? key}) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            key: key,
            label: Text(label),
            selected: selected,
            onSelected: (_) => onTap(),
            showCheckmark: false,
            backgroundColor: AppColors.surfaceVariant,
            selectedColor: AppColors.emerald.withValues(alpha: 0.22),
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.emerald : AppColors.onSurface,
            ),
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999)),
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Todos', filter.status == null,
              () => set(filter.copyWith(clearStatus: true))),
          for (final s in SubscriptionStatus.values)
            chip(
              s.label,
              filter.status == s,
              () => set(filter.copyWith(status: s)),
              key: Key('filter-${s.name}'),
            ),
        ],
      ),
    );
  }
}

class _TenantTile extends StatelessWidget {
  const _TenantTile({
    required this.tenant,
    required this.busy,
    required this.onReactivate,
    required this.onSoftLock,
    required this.onHardLock,
    required this.onExtend,
  });

  final TenantSummary tenant;
  final bool busy;
  final VoidCallback onReactivate;
  final VoidCallback onSoftLock;
  final VoidCallback onHardLock;
  final VoidCallback onExtend;

  @override
  Widget build(BuildContext context) {
    final t = tenant;
    final color = switch (t.status) {
      SubscriptionStatus.active => AppColors.emerald,
      SubscriptionStatus.softLock => AppColors.warning,
      SubscriptionStatus.hardLock => AppColors.error,
    };
    final inv = t.pendingInvoice;
    final detail = inv == null
        ? 'Sin factura pendiente'
        : t.daysOverdue > 0
            ? 'Vencida hace ${t.daysOverdue} días · ${mxn(inv.amountMxn)}'
            : 'Vence ${shortDate(inv.dueDate)} · ${mxn(inv.amountMxn)}';

    return _Card(
      key: Key('tenant-${t.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        t.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        t.status.label,
                        key: Key('tenantStatus-${t.id}'),
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${t.code} · ${t.plan?.name ?? 'sin plan'} · $detail',
                  style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.onSurfaceMuted,
                      height: 1.3),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            key: Key('tenantMenu-${t.id}'),
            enabled: !busy,
            tooltip: 'Acciones',
            color: AppColors.surface,
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.onSurfaceMuted),
            onSelected: (v) => switch (v) {
              'reactivate' => onReactivate(),
              'soft' => onSoftLock(),
              'hard' => onHardLock(),
              'extend' => onExtend(),
              _ => null,
            },
            itemBuilder: (_) => [
              if (t.status != SubscriptionStatus.active)
                const PopupMenuItem(
                    value: 'reactivate', child: Text('Reactivar')),
              if (inv != null)
                const PopupMenuItem(
                    value: 'extend', child: Text('Extender plazo 7 días')),
              if (t.status != SubscriptionStatus.softLock)
                const PopupMenuItem(
                    value: 'soft', child: Text('Poner en solo lectura')),
              if (t.status != SubscriptionStatus.hardLock)
                const PopupMenuItem(value: 'hard', child: Text('Suspender')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

/// Motivo del rechazo. Widget propio: el `TextEditingController` vive y muere
/// con el diálogo (disponerlo al cerrar rompe la animación de salida).
class _RejectNotesDialog extends StatefulWidget {
  const _RejectNotesDialog({required this.item});
  final ValidationInboxItem item;

  @override
  State<_RejectNotesDialog> createState() => _RejectNotesDialogState();
}

class _RejectNotesDialogState extends State<_RejectNotesDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.length < 3) {
      setState(() => _error = 'Escribe el motivo.');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Rechazar aviso'),
      // Ancho fijo: un TextField dentro del IntrinsicWidth del diálogo no
      // sabe medirse.
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.tenantName} (${item.tenantCode}) · ${mxn(item.invoiceAmountMxn)} MXN\n'
              '${item.validation.method.label} · ref. ${item.validation.reference}\n'
              'El comercio leerá este motivo.',
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('rejectNotesField'),
              controller: _controller,
              autofocus: true,
              maxLines: 2,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Motivo',
                hintText: 'Ej. No aparece en el banco con esa clave',
                errorText: _error,
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirmReject'),
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.onSurface,
          ),
          child: const Text('Rechazar'),
        ),
      ],
    );
  }
}
