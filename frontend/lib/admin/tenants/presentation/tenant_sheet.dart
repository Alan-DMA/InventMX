import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../features/management/domain/tenant_role.dart' show RoleCodeLabel;
import '../../cases/presentation/widgets/cases_widgets.dart';
import '../../core/admin_format.dart';
import '../../core/admin_http.dart';
import '../../core/store_status.dart';
import '../../router/admin_routes.dart';
import '../../session/admin_session.dart';
import '../../today/presentation/today_providers.dart';
import '../data/support_actions_repository.dart';
import '../domain/tenant_models.dart';
import 'support_action_dialog.dart';
import 'support_session_dialog.dart';
import 'tenant_providers.dart';

/// Ficha de la tienda en panel deslizante (≈480 px; pantalla completa en
/// móvil; Esc cierra). Sólo metadatos (P2): suscripción informativa, lo que
/// está en curso, diagnóstico, sus casos y su actividad. Las acciones llegan
/// en la etapa 3d.
class TenantSheet extends ConsumerStatefulWidget {
  const TenantSheet({super.key, required this.tenantId, required this.onClose});

  final String tenantId;
  final VoidCallback onClose;

  static const width = 480.0;
  static const fullScreenBelow = 700.0;

  @override
  ConsumerState<TenantSheet> createState() => _TenantSheetState();
}

class _TenantSheetState extends ConsumerState<TenantSheet> {
  final _focus = FocusNode(debugLabel: 'tenantSheet');

  /// Lo que pasó con la última acción, dicho en la ficha (no sólo un aviso fugaz).
  String? _notice;
  final _noticeKey = GlobalKey(debugLabel: 'tenantSheetNotice');

  Future<void> _run(SupportActionKind kind, TenantDetail detail) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await showSupportAction(context, kind, detail);
    if (outcome == null || !mounted) return;
    // "Hoy" y los conteos cambian con la acción
    if (ref.exists(feedProvider)) ref.read(feedProvider.notifier).refreshSilently();
    if (ref.exists(metricsProvider)) ref.invalidate(metricsProvider);
    if (outcome.storeDeleted) {
      messenger.showSnackBar(SnackBar(content: Text(outcome.message)));
      widget.onClose();
      return;
    }
    setState(() => _notice = outcome.message);
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _noticeKey.currentContext;
      if (target != null) Scrollable.ensureVisible(target, alignment: 0.2);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).width;
    final full = screen < TenantSheet.fullScreenBelow;
    final detail = ref.watch(tenantDetailProvider(widget.tenantId));
    final name = detail.valueOrNull?.summary.name;

    return Stack(
      children: [
        Positioned.fill(
          child: ModalBarrier(
            color: Colors.black54,
            dismissible: true,
            onDismiss: widget.onClose,
            semanticsLabel: 'Cerrar la ficha',
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: full ? screen : TenantSheet.width,
            child: Focus(
              focusNode: _focus,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                  widget.onClose();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Semantics(
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: name == null ? 'Ficha de la tienda' : 'Ficha de $name',
                child: Material(
                  key: const Key('tenantSheet'),
                  // Sin sombra de elevación: el velo y el borde bastan (el mundo no usa sombras duras)
                  color: AppColors.darkSlate,
                  shape: const Border(left: BorderSide(color: AppColors.border)),
                  child: detail.when(
                    loading: () => _Frame(onClose: widget.onClose, child: const CasesSkeleton(rows: 5)),
                    error: (e, _) => _Frame(
                      onClose: widget.onClose,
                      child: CasesErrorBlock(
                        message:
                            e is AdminApiException && e.statusCode == 404 ? 'Esta tienda ya no existe.' : e.toString(),
                        onRetry: () => ref.invalidate(tenantDetailProvider(widget.tenantId)),
                      ),
                    ),
                    data: (d) => _Frame(
                      onClose: widget.onClose,
                      title: d.summary.name,
                      child: _Body(
                        detail: d,
                        notice: _notice,
                        noticeKey: _noticeKey,
                        onDismissNotice: () => setState(() => _notice = null),
                        onAction: (kind) => _run(kind, d),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.onClose, required this.child, this.title});
  final VoidCallback onClose;
  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title ?? '',
                      key: const Key('tenantSheetTitle'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('tenantSheetClose'),
                  tooltip: 'Cerrar (Esc)',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, color: AppColors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      );
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.detail,
    required this.onAction,
    required this.onDismissNotice,
    required this.noticeKey,
    this.notice,
  });
  final TenantDetail detail;
  final ValueChanged<SupportActionKind> onAction;
  final String? notice;
  final GlobalKey noticeKey;
  final VoidCallback onDismissNotice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = detail.summary;
    final now = ref.read(adminClockProvider)();
    final (statusLabel, statusColor) = storeStatus(t.status, t.lockReason);

    return ListView(
      key: const Key('tenantSheetBody'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: statusLabel,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: statusColor),
            ),
            TextSpan(
              text: '  ·  ${planLabel(t.plan)}  ·  desde ${adminDate(t.createdAt)}',
              style: const TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted),
            ),
          ]),
          key: const Key('tenantSheetStatus'),
        ),
        const SizedBox(height: 4),
        Text(
          [
            t.slug,
            if (t.ownerName != null) 'dueño: ${t.ownerName}',
            if (t.ownerEmail != null) t.ownerEmail!,
          ].join(' · '),
          style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4),
        ),
        if (detail.suspensionReason != null) ...[
          const SizedBox(height: 14),
          _Note(
            key: const Key('tenantSheetSuspension'),
            color: AppColors.error,
            icon: Icons.block_rounded,
            text: 'Suspendida por soporte: ${detail.suspensionReason}',
          ),
        ],
        if (_InProgress.hasItems(detail.support)) _InProgress(support: detail.support),
        _Actions(
            detail: detail, onAction: onAction, notice: notice, noticeKey: noticeKey, onDismissNotice: onDismissNotice),
        _Section(
          title: 'Suscripción',
          children: [
            _Row(
                'Vigencia',
                switch (t.entitlement) {
                  'VIGENTE' => t.paidUntil == null ? 'Vigente' : 'Vigente hasta ${adminDate(t.paidUntil!)}',
                  'GRACIA' => t.graceUntil == null ? 'En gracia' : 'En gracia hasta ${adminDate(t.graceUntil!)}',
                  'VENCIDA' => t.paidUntil == null ? 'Vencida' : 'Venció el ${adminDate(t.paidUntil!)}',
                  _ => 'Sin fecha',
                }),
            _Row(
              'Cobro',
              t.subscriptionSource == 'GOOGLE_PLAY'
                  ? 'Google Play'
                  : 'Sin conectar a Google Play aún${_sourceNote(t.subscriptionSource)}',
            ),
            _Row('Usuarios', '${t.usersCount} de ${t.usersLimit}'),
            _Row('Última actividad', t.lastActivityAt == null ? 'Sin registro' : adminAgo(t.lastActivityAt!, now)),
          ],
        ),
        _Section(
          title: 'Diagnóstico',
          children: [
            _Row(
                'Catálogo web',
                switch (detail.catalogEnabled) {
                  true => 'Encendido',
                  false => 'Apagado',
                  null => 'Nunca lo configuró',
                }),
            const SizedBox(height: 10),
            const _Label('Almacenes'),
            for (final w in detail.warehouses)
              _Line(
                [w.name, if (w.isDefault) 'principal', if (!w.isActive) 'inactivo'].join(' · '),
                muted: !w.isActive,
              ),
            if (detail.warehouses.isEmpty) const _Line('Sin almacenes', muted: true),
            const SizedBox(height: 10),
            const _Label('Usuarios'),
            for (final u in detail.users)
              _Line(
                [
                  u.fullName,
                  if (u.role != null) u.role!.roleLabel,
                  u.email,
                  if (!u.isActive)
                    'inactivo'
                  else
                    u.lastLoginAt == null ? 'nunca entró' : 'entró ${adminAgo(u.lastLoginAt!, now)}',
                ].join(' · '),
                muted: !u.isActive,
              ),
          ],
        ),
        _TenantCases(tenantId: t.id),
        _Section(
          title: 'Actividad',
          children: [
            if (detail.activity.isEmpty) const _Line('Sin acciones de soporte todavía.', muted: true),
            for (final a in detail.activity.take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.summary, style: const TextStyle(fontSize: 13.5, color: AppColors.onSurface, height: 1.4)),
                    Text(
                      [adminMoment(a.occurredAt), if ((a.reason ?? '').isNotEmpty) '"${a.reason}"'].join(' · '),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted, height: 1.4),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _sourceNote(String? source) => switch (source) {
        'TRIAL' => ' · periodo de prueba',
        'COURTESY' => ' · cortesía',
        'MANUAL' => ' · pago manual',
        'GATEWAY' => ' · pasarela',
        _ => '',
      };
}

class _InProgress extends StatelessWidget {
  const _InProgress({required this.support});
  final SupportState support;

  /// La eliminación pendiente la dice "Acciones" (con Aprobar/Cancelar): aquí
  /// sólo lo demás.
  static bool hasItems(SupportState s) =>
      s.accessGrantedUntil != null || s.assistedCodeUntil != null || s.lastExportStatus != null;

  @override
  Widget build(BuildContext context) => _Section(
        title: 'En curso',
        children: [
          if (support.accessGrantedUntil != null)
            _Note(
              color: AppColors.skyBlue,
              icon: Icons.visibility_outlined,
              text: 'El dueño concedió acceso de soporte hasta ${adminMoment(support.accessGrantedUntil!)}.',
            ),
          if (support.assistedCodeUntil != null)
            _Note(
              color: AppColors.skyBlue,
              icon: Icons.key_outlined,
              text: 'Código de recuperación enviado, sin usar (vence ${adminMoment(support.assistedCodeUntil!)}).',
            ),
          if (support.lastExportStatus != null)
            _Note(
              color: support.lastExportStatus == 'FAILED' ? AppColors.error : AppColors.skyBlue,
              icon: Icons.download_rounded,
              text: switch (support.lastExportStatus) {
                'PENDING' => 'Exportación de datos en proceso.',
                'FAILED' => 'La última exportación falló.',
                _ => 'La última exportación llegó al correo del dueño.',
              },
            ),
        ],
      );
}

/// Acciones de soporte (P36: arriba). Cada botón dice el verbo; si no aplica,
/// se ve desactivado y dice por qué. Eliminar va aparte y en rojo.
class _Actions extends ConsumerWidget {
  const _Actions({
    required this.detail,
    required this.onAction,
    required this.noticeKey,
    required this.onDismissNotice,
    this.notice,
  });
  final TenantDetail detail;
  final ValueChanged<SupportActionKind> onAction;

  /// Lo que pasó con la última acción: aquí, sobre los botones, donde está la
  /// atención del operador (al principio de la ficha quedaba fuera de la vista).
  final String? notice;
  final GlobalKey noticeKey;
  final VoidCallback onDismissNotice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = detail.support;
    final me = ref.watch(adminSessionProvider.select((x) => x.session?.operatorId));
    final mine = s.hasPendingDeletion && me != null && s.deletionRequestedById == me;
    final exporting = s.exportInProgress;

    // Lo irreversible se distingue: rojo y con el verbo completo; deshacer no
    final dangerStyle = OutlinedButton.styleFrom(
      foregroundColor: AppColors.error,
      side: BorderSide(color: AppColors.error.withValues(alpha: 0.6)),
    );

    Widget action(String key, IconData icon, String label, SupportActionKind kind,
            {String? disabledWhy, bool danger = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                key: Key(key),
                onPressed: disabledWhy == null ? () => onAction(kind) : null,
                style: danger ? dangerStyle : null,
                icon: Icon(icon, size: 18),
                label: Text(label),
              ),
              if (disabledWhy != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4),
                  child: Text(disabledWhy, style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted)),
                ),
            ],
          ),
        );

    return _Section(
      title: 'Acciones',
      children: [
        if (notice != null)
          Semantics(
            liveRegion: true,
            child: Container(
              key: noticeKey,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: AppColors.skyBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.skyBlue.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_rounded, size: 18, color: AppColors.skyBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      notice!,
                      key: const Key('tenantSheetNotice'),
                      style: const TextStyle(fontSize: 13.5, color: AppColors.onSurface, height: 1.4),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar aviso',
                    onPressed: onDismissNotice,
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
          ),
        _SupportSessionBlock(detail: detail),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            action('tenantActionRecovery', Icons.key_outlined, 'Enviar código de acceso', SupportActionKind.recovery),
            action('tenantActionGift', Icons.card_giftcard_outlined, 'Regalar días', SupportActionKind.giftDays),
            if (detail.suspendedForAbuse)
              action('tenantActionLift', Icons.lock_open_outlined, 'Levantar la suspensión', SupportActionKind.lift)
            else
              action('tenantActionSuspend', Icons.block_rounded, 'Suspender por abuso', SupportActionKind.suspend),
            action(
              'tenantActionExport',
              Icons.download_rounded,
              'Exportar sus datos',
              SupportActionKind.export,
              disabledWhy: exporting ? 'Ya hay una exportación en proceso.' : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.hasPendingDeletion) ...[
              Text(
                mine
                    ? 'Pediste eliminarla; falta que otro fundador la apruebe (vence el ${adminDate(s.deletionExpiresAt!)}).'
                    : '${s.deletionRequestedBy ?? 'Otro fundador'} pidió eliminarla'
                        '${(s.deletionReason ?? '').isEmpty ? '' : ': "${s.deletionReason}"'} '
                        '(vence el ${adminDate(s.deletionExpiresAt!)}).',
                key: const Key('tenantDeletionPending'),
                style: const TextStyle(fontSize: 13.5, color: AppColors.onSurface, height: 1.4),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (!mine)
                    action('tenantActionApprove', Icons.delete_forever_outlined, 'Aprobar la eliminación',
                        SupportActionKind.approveDeletion,
                        danger: true),
                  action('tenantActionCancelDeletion', Icons.undo_rounded, 'Cancelar la eliminación',
                      SupportActionKind.cancelDeletion),
                ],
              ),
            ] else ...[
              if (s.deletionExpired)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('La solicitud anterior venció sin segunda aprobación.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted)),
                ),
              action(
                'tenantActionDelete',
                Icons.delete_outline_rounded,
                'Eliminar la tienda',
                SupportActionKind.requestDeletion,
                disabledWhy: exporting ? 'Hay una exportación en proceso: espera a que llegue.' : null,
                danger: true,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Sesión de soporte de sólo lectura (etapa 4, P37–P42): ver la tienda como
/// la ve el dueño, con su permiso. Sin permiso, el botón dice por qué.
class _SupportSessionBlock extends ConsumerStatefulWidget {
  const _SupportSessionBlock({required this.detail});
  final TenantDetail detail;

  @override
  ConsumerState<_SupportSessionBlock> createState() => _SupportSessionBlockState();
}

class _SupportSessionBlockState extends ConsumerState<_SupportSessionBlock> {
  bool _busy = false;
  String? _error;

  String get _tenantId => widget.detail.summary.id;

  void _patch(List<SupportSessionInfo> Function(List<SupportSessionInfo>) change) => ref
      .read(tenantDetailProvider(_tenantId).notifier)
      .patchSupport((s) => s.copyWith(sessions: change(s.sessions)));

  void _refreshToday() {
    if (ref.exists(feedProvider)) ref.read(feedProvider.notifier).refreshSilently();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    final link = await showSupportSessionDialog(context, widget.detail);
    if (link == null || !mounted) return;
    _patch((list) => [...list.where((x) => x.id != link.session.id), link.session]);
    _refreshToday();
  }

  Future<void> _reopen(SupportSessionInfo session) async {
    // La pestaña se abre en blanco dentro del clic y se lleva a su enlace al llegar
    final tab = ref.read(openPendingTabProvider)();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await ref.read(supportActionsRepositoryProvider).newSupportLink(session.id);
      tab.navigate(supportTabUrl(link.code));
      _patch((list) => [for (final x in list) x.id == session.id ? link.session : x]);
    } catch (e) {
      tab.close();
      final error = toAdminError(e, 'No pudimos generar otro enlace.');
      // La sesión ya había terminado: se quita de la ficha
      if (error.statusCode == 401) _patch((list) => list.where((x) => x.id != session.id).toList());
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end(SupportSessionInfo session) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(supportActionsRepositoryProvider).endSupportSession(session.id);
      _patch((list) => list.where((x) => x.id != session.id).toList());
      _refreshToday();
    } catch (e) {
      if (mounted) setState(() => _error = toAdminError(e, 'No pudimos terminar la sesión.').message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.detail.support;
    final me = ref.watch(adminSessionProvider.select((x) => x.session?.operatorId));
    final now = ref.read(adminClockProvider)();
    // Lo que ya venció según el reloj se deja de mostrar (el servidor ya no la acepta)
    final live = s.sessions.where((x) => x.until == null || x.until!.isAfter(now)).toList();
    final mine = live.where((x) => x.operatorId == me).firstOrNull;
    final others = live.where((x) => x.operatorId != me).toList();
    final granted = s.accessGrantedUntil != null && s.accessGrantedUntil!.isAfter(now);

    return Column(
      key: const Key('tenantSessionBlock'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mine != null) ...[
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Tu sesión de soporte · ', style: TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(
                text: mine.waiting
                    ? 'enlace listo, sin abrir (vale hasta las ${_hhmm(mine.linkExpiresAt!)})'
                    : 'abierta, quedan ${adminSpan(mine.expiresAt!.difference(now))}',
              ),
            ]),
            key: const Key('tenantSessionMine'),
            style: const TextStyle(fontSize: 13.5, color: AppColors.onSurface, height: 1.4),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                key: const Key('tenantSessionReopen'),
                onPressed: _busy ? null : () => _reopen(mine),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                // Mientras nunca se haya abierto, es la primera vez: "Abrir de nuevo" mentiría (P39)
                label: Text(mine.waiting ? 'Abrir la tienda' : 'Abrir de nuevo'),
              ),
              OutlinedButton(
                key: const Key('tenantSessionEnd'),
                onPressed: _busy ? null : () => _end(mine),
                child: const Text('Terminar'),
              ),
            ],
          ),
        ] else ...[
          OutlinedButton.icon(
            key: const Key('tenantActionViewStore'),
            onPressed: granted && !_busy ? _start : null,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Ver la tienda (sólo lectura)'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4),
            child: Text(
              granted
                  ? 'Con el permiso del dueño, vigente hasta ${adminMoment(s.accessGrantedUntil!)}.'
                  : 'El dueño no ha dado acceso. Pídeselo desde su caso.',
              key: const Key('tenantViewStoreWhy'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted),
            ),
          ),
        ],
        for (final o in others)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              o.waiting
                  ? '${o.operatorName} tiene un enlace de soporte sin abrir.'
                  : '${o.operatorName} está viendo la tienda (sólo lectura) · quedan ${adminSpan(o.expiresAt!.difference(now))}.',
              style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(_error!,
                  key: const Key('tenantSessionError'),
                  style: const TextStyle(fontSize: 13, color: AppColors.error, height: 1.4)),
            ),
          ),
      ],
    );
  }

  static String _hhmm(DateTime d) {
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _TenantCases extends ConsumerWidget {
  const _TenantCases({required this.tenantId});
  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cases = ref.watch(tenantCasesProvider(tenantId));
    return _Section(
      title: 'Casos',
      children: [
        cases.when(
          loading: () => const _Line('Cargando…', muted: true),
          error: (e, _) => _Line(e.toString(), muted: true),
          data: (items) => items.isEmpty
              ? const _Line('Sin casos de soporte.', muted: true)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final c in items)
                      InkWell(
                        key: Key('tenantCase_${c.id}'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => context.go(AdminRoutes.casePath(c.id)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Caso ${c.number} · ${c.topicTitle}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5, color: AppColors.onSurface),
                                ),
                              ),
                              const SizedBox(width: 8),
                              DeskStatusChip(c.status),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ── Piezas ──────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onSurface),
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 132,
              child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted)),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(fontSize: 13.5, color: AppColors.onSurface, height: 1.4)),
            ),
          ],
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurfaceMuted)),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.text, {this.muted = false});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: TextStyle(fontSize: 13.5, color: muted ? AppColors.onSurfaceMuted : AppColors.onSurface, height: 1.4),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.color, required this.icon, required this.text});
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text, style: const TextStyle(fontSize: 13.5, color: AppColors.onSurface, height: 1.4))),
          ],
        ),
      );
}
