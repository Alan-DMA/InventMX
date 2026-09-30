import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../cases/presentation/cases_providers.dart';
import '../core/admin_colors.dart';
import '../tenants/presentation/store_search.dart';
import '../tenants/presentation/tenant_sheet.dart';
import '../today/presentation/today_providers.dart';
import '../router/admin_routes.dart';
import '../session/admin_session.dart';
import 'platform_strip.dart';

/// Armazón del panel: franja fija arriba, navegación con texto a la izquierda
/// (Hoy · Casos · Bitácora · Temas de ayuda, P28) y la sección a la derecha.
/// En pantalla chica la navegación pasa a una fila bajo la franja.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.uri, required this.child});

  final String location;

  /// La dirección completa: `?tienda=<id>` abre la ficha encima de la sección.
  final Uri uri;
  final Widget child;

  static const railWidth = 220.0;
  static const compactBelow = 900.0;

  Future<void> _search(BuildContext context) async {
    final picked = await showStoreSearch(context);
    if (picked != null && context.mounted) context.go(AdminRoutes.withStore(uri, picked.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(adminSessionProvider).session;
    final compact = MediaQuery.sizeOf(context).width < compactBelow;
    final waiting = ref.watch(waitingCountProvider).valueOrNull;
    final nav = _AdminNav(location: location, horizontal: compact, waiting: waiting);
    final storeId = uri.queryParameters[AdminRoutes.storeParam];

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      body: _Poller(
        // Ctrl K desde cualquier sección (P15: buscador global)
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _search(context),
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => _search(context),
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                Column(
                  children: [
                    const PlatformStrip(),
                    if (session != null && session.enteredWithRecoveryCode)
                      _RecoveryNotice(
                        remaining: session.recoveryCodesRemaining,
                        onDismiss: () => ref.read(adminSessionProvider.notifier).dismissRecoveryNotice(),
                      ),
                    if (compact) ...[
                      nav,
                      const Divider(height: 1),
                      Expanded(child: child),
                    ] else
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: railWidth, child: nav),
                            const VerticalDivider(width: 1, color: AppColors.border),
                            Expanded(child: child),
                          ],
                        ),
                      ),
                  ],
                ),
                if (storeId != null)
                  Positioned.fill(
                    top: PlatformStrip.height,
                    child: TenantSheet(
                      key: ValueKey('sheet_$storeId'),
                      tenantId: storeId,
                      onClose: () => context.go(AdminRoutes.withoutStore(uri)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cada 60 s, en silencio: el contador de "Casos", la cola y "Hoy" si están
/// abiertos (P33). Sin sonidos ni emergentes.
class _Poller extends ConsumerStatefulWidget {
  const _Poller({required this.child});
  final Widget child;

  static const every = Duration(seconds: 60);

  @override
  ConsumerState<_Poller> createState() => _PollerState();
}

class _PollerState extends ConsumerState<_Poller> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_Poller.every, (_) {
      if (!mounted) return;
      ref.invalidate(waitingCountProvider);
      if (ref.exists(caseListProvider)) ref.read(caseListProvider.notifier).refreshSilently();
      if (ref.exists(feedProvider)) ref.read(feedProvider.notifier).refreshSilently();
      if (ref.exists(metricsProvider)) ref.invalidate(metricsProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _NavEntry {
  const _NavEntry(this.label, this.icon, this.path, this.key);
  final String label;
  final IconData icon;
  final String path;
  final String key;
}

const _entries = [
  _NavEntry('Hoy', Icons.today_outlined, AdminRoutes.today, 'adminNavToday'),
  _NavEntry('Casos', Icons.forum_outlined, AdminRoutes.cases, 'adminNavCases'),
  _NavEntry('Bitácora', Icons.history_rounded, AdminRoutes.audit, 'adminNavAudit'),
  _NavEntry('Temas de ayuda', Icons.menu_book_outlined, AdminRoutes.helpTopics, 'adminNavTopics'),
];

class _AdminNav extends StatelessWidget {
  const _AdminNav({required this.location, required this.horizontal, this.waiting});
  final String location;
  final bool horizontal;

  /// Casos que esperan respuesta (sólo eso cuenta).
  final int? waiting;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final e in _entries)
        _NavItem(
          entry: e,
          selected: location == e.path || location.startsWith('${e.path}/'),
          dense: horizontal,
          count: e.path == AdminRoutes.cases && (waiting ?? 0) > 0 ? waiting : null,
        ),
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Secciones del panel',
      child: horizontal
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(children: items),
            )
          : ListView(padding: const EdgeInsets.fromLTRB(12, 16, 12, 16), children: items),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.entry, required this.selected, required this.dense, this.count});
  final _NavEntry entry;
  final bool selected;
  final bool dense;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AdminColors.indigo : AppColors.onSurfaceMuted;
    final label = Text(
      entry.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: selected ? AdminColors.indigo : AppColors.onSurface,
      ),
    );
    return Padding(
      padding: dense ? const EdgeInsets.only(right: 4) : const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: selected,
        button: true,
        label: count == null ? null : '${entry.label}, $count esperando',
        excludeSemantics: count != null,
        child: Material(
          color: selected ? AdminColors.indigoSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: Key(entry.key),
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.go(entry.path),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 10),
              child: Row(
                mainAxisSize: dense ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  Icon(entry.icon, size: 18, color: color),
                  const SizedBox(width: 12),
                  // En la fila horizontal el ancho no tiene tope: ahí no cabe un Flexible
                  if (dense) label else Flexible(child: label),
                  if (count != null) ...[
                    if (!dense) const Spacer() else const SizedBox(width: 8),
                    Text(
                      '$count',
                      key: Key('${entry.key}Count'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.indigo,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Entró con un código de recuperación: se le dice cuántos le quedan y qué
/// hacer si perdió el teléfono. Se cierra con un toque.
class _RecoveryNotice extends StatelessWidget {
  const _RecoveryNotice({required this.remaining, required this.onDismiss});
  final int remaining;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final low = remaining <= 2;
    final color = low ? AdminColors.amber : AppColors.skyBlue;
    return Container(
      key: const Key('adminRecoveryNotice'),
      color: color.withValues(alpha: 0.1),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.key_outlined, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Entraste con un código de recuperación. '
              '${remaining == 1 ? 'Te queda 1' : 'Te quedan $remaining'}. '
              'Si perdiste el teléfono, pide al otro fundador que restablezca tu Authenticator.',
              style: const TextStyle(fontSize: 13, color: AppColors.onSurface, height: 1.35),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar aviso',
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}

/// Sección que llega en una sub-etapa posterior: lo dice con honestidad y
/// señala cuál (el panel se construye por partes, P28).
class AdminPendingSection extends StatelessWidget {
  const AdminPendingSection({super.key, required this.title, required this.arrivesIn, required this.what});
  final String title;
  final String arrivesIn;
  final String what;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$what Llega en la $arrivesIn.',
                  style: const TextStyle(fontSize: 14.5, color: AppColors.onSurfaceMuted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
}
