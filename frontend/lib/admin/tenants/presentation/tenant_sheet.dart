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
import '../domain/tenant_models.dart';
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
                      child: _Body(detail: d),
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
  const _Body({required this.detail});
  final TenantDetail detail;

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
        if (!detail.support.isEmpty) _InProgress(support: detail.support),
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
        const SizedBox(height: 8),
        const Text(
          'Las acciones de soporte (regalar días, suspender, recuperación asistida, exportar y eliminar) llegan en la '
          'etapa 3d.',
          style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted, height: 1.45),
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

  @override
  Widget build(BuildContext context) => _Section(
        title: 'En curso',
        children: [
          if (support.deletionExpiresAt != null)
            _Note(
              color: AppColors.error,
              icon: Icons.delete_outline_rounded,
              text: 'Eliminación pedida por ${support.deletionRequestedBy ?? 'un fundador'}; falta la segunda '
                  'aprobación (vence el ${adminDate(support.deletionExpiresAt!)}).',
            ),
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
