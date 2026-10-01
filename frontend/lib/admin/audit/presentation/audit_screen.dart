import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../cases/presentation/widgets/cases_widgets.dart';
import '../../core/admin_colors.dart';
import '../../core/admin_format.dart';
import '../../session/admin_session.dart';
import '../../tenants/presentation/store_search.dart';
import '../../tenants/presentation/tenant_providers.dart';
import '../domain/audit_models.dart';
import 'audit_providers.dart';

/// Bitácora (etapa 3e): todo lo que se hizo desde el panel, en palabras y con
/// el motivo, filtrable por tipo, tienda y "mis acciones". La integridad de la
/// cadena se verifica al abrirla; si está rota, el armazón lo dice en todo el
/// panel.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(chainProvider) is ChainUnknown) ref.read(chainProvider.notifier).verify();
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(auditListProvider);
    final filter = ref.watch(auditFilterProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      key: const Key('auditList'),
      padding: EdgeInsets.fromLTRB(wide ? 40 : 20, 28, wide ? 40 : 20, 48),
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: const Text('Bitácora',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                ),
                const SizedBox(height: 8),
                const _Integrity(),
                const SizedBox(height: 20),
                _Filters(filter: filter),
                const SizedBox(height: 16),
                ...list.when(
                  skipLoadingOnRefresh: true,
                  loading: () => [const CasesSkeleton(rows: 6)],
                  error: (e, _) => [
                    CasesErrorBlock(message: e.toString(), onRetry: () => ref.invalidate(auditListProvider)),
                  ],
                  data: (state) => [
                    if (state.items.isEmpty)
                      _Empty(filtered: filter.isFiltered)
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < state.items.length; i++) ...[
                              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                              _EntryRow(entry: state.items[i]),
                            ],
                          ],
                        ),
                      ),
                    if (state.moreError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(state.moreError!, style: const TextStyle(fontSize: 13, color: AppColors.error)),
                      ),
                    if (state.hasMore)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            key: const Key('auditLoadMore'),
                            onPressed: state.loadingMore ? null : () => ref.read(auditListProvider.notifier).loadMore(),
                            child: Text(state.loadingMore
                                ? 'Cargando…'
                                : 'Cargar más (${state.items.length} de ${state.total})'),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// La cadena de hashes: íntegra, verificando, rota o sin poder verificar.
class _Integrity extends ConsumerWidget {
  const _Integrity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chain = ref.watch(chainProvider);
    final (IconData icon, Color color, String text) = switch (chain) {
      ChainUnknown() || ChainChecking() => (
          Icons.hourglass_empty_rounded,
          AppColors.onSurfaceMuted,
          'Verificando la integridad…'
        ),
      ChainIntact(:final checked) => (
          Icons.verified_outlined,
          AppColors.onSurfaceMuted,
          'Íntegra: $checked ${checked == 1 ? 'registro verificado' : 'registros verificados'}.'
        ),
      ChainBroken(:final brokenAtId) => (
          Icons.gpp_bad_outlined,
          AppColors.error,
          'Alterada fuera del panel${brokenAtId == null ? '' : ' a partir del registro #$brokenAtId'}.'
        ),
      ChainCheckFailed(:final message) => (Icons.wifi_off_rounded, AdminColors.amber, 'No pudimos verificar: $message'),
    };
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(text,
                  key: const Key('auditIntegrity'),
                  style:
                      TextStyle(fontSize: 13.5, color: chain is ChainBroken ? AppColors.error : AppColors.onSurface)),
            ),
          ],
        ),
        TextButton(
          key: const Key('auditVerify'),
          onPressed: chain is ChainChecking ? null : () => ref.read(chainProvider.notifier).verify(),
          child: const Text('Verificar ahora'),
        ),
      ],
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.filter});
  final AuditFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final set = ref.read(auditFilterProvider.notifier);
    final canFilterMine = ref.watch(adminSessionProvider.select((s) => s.session?.operatorId)) != null;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ActionMenu(
          selected: filter.action,
          onSelected: (code) =>
              set.state = code == null ? filter.copyWith(clearAction: true) : filter.copyWith(action: code),
        ),
        if (filter.tenantId == null)
          OutlinedButton.icon(
            key: const Key('auditTenantFilter'),
            onPressed: () async {
              final picked = await showStoreSearch(context);
              if (picked != null) set.state = filter.copyWith(tenantId: picked.id, tenantName: picked.name);
            },
            icon: const Icon(Icons.storefront_outlined, size: 18),
            label: const Text('Tienda: todas'),
          )
        else
          InputChip(
            key: const Key('auditTenantChip'),
            label: Text('Tienda: ${filter.tenantName ?? filter.tenantId}'),
            onDeleted: () => set.state = filter.copyWith(clearTenant: true),
            deleteButtonTooltipMessage: 'Quitar el filtro de tienda',
          ),
        FilterChip(
          key: const Key('auditOnlyMine'),
          label: const Text('Sólo mis acciones'),
          selected: filter.onlyMine,
          onSelected: canFilterMine ? (v) => set.state = filter.copyWith(onlyMine: v) : null,
          tooltip: canFilterMine ? null : 'Vuelve a entrar al panel para usar este filtro',
        ),
        FilterChip(
          key: const Key('auditShowNoise'),
          label: const Text('Mostrar aperturas de ficha y accesos'),
          selected: filter.showNoise,
          onSelected: (v) => set.state = filter.copyWith(showNoise: v),
        ),
      ],
    );
  }
}

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({required this.selected, required this.onSelected});
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        key: const Key('auditActionFilter'),
        tooltip: 'Filtrar por tipo de acción',
        color: AppColors.surface,
        onSelected: (v) => onSelected(v == '' ? null : v),
        itemBuilder: (_) => [
          const PopupMenuItem(value: '', child: Text('Todas las acciones')),
          for (final group in auditActionGroups) ...[
            PopupMenuItem<String>(
              enabled: false,
              height: 32,
              child: Text(group.title,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.onSurfaceMuted)),
            ),
            for (final (code, label) in group.actions)
              PopupMenuItem(value: code, key: Key('auditAction_$code'), child: Text(label)),
          ],
        ],
        child: IgnorePointer(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.filter_list_rounded, size: 18),
            label: Text(selected == null ? 'Todas las acciones' : auditActionLabel(selected!) ?? selected!),
          ),
        ),
      );
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (entry.operatorName != null) entry.operatorName!,
      if (accessActions.contains(entry.action) && entry.ipAddress != null) 'IP ${entry.ipAddress}',
    ].join(' · ');
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              adminMoment(entry.occurredAt),
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.onSurfaceMuted,
                height: 1.45,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.summary, style: const TextStyle(fontSize: 14, color: AppColors.onSurface, height: 1.4)),
                if ((entry.reason ?? '').isNotEmpty)
                  Text('"${entry.reason}"',
                      style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4)),
                if (details.isNotEmpty)
                  Text(details, style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted, height: 1.4)),
              ],
            ),
          ),
          if (entry.targetTenantId != null) const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceMuted),
        ],
      ),
    );
    if (entry.targetTenantId == null) return content;
    return InkWell(
      key: Key('auditEntry_${entry.id}'),
      onTap: () => openStore(context, entry.targetTenantId!),
      child: content,
    );
  }
}

class _Empty extends ConsumerWidget {
  const _Empty({required this.filtered});
  final bool filtered;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        key: const Key('auditEmpty'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(filtered ? 'Sin registros con este filtro.' : 'Todavía no hay registros.',
                style: const TextStyle(fontSize: 14, color: AppColors.onSurface)),
            if (filtered) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('auditClearFilters'),
                onPressed: () => ref.read(auditFilterProvider.notifier).state =
                    AuditFilter(showNoise: ref.read(auditFilterProvider).showNoise),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text('Quitar los filtros'),
              ),
            ],
          ],
        ),
      );
}
