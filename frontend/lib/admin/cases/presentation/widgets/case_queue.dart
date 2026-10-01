import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../core/admin_colors.dart';
import '../../../core/admin_format.dart';
import '../../../session/admin_session.dart';
import '../../domain/desk_case.dart';
import '../cases_providers.dart';
import 'cases_widgets.dart';

/// La cola: pestañas, buscador y renglones. En "Esperando" manda cuánto lleva
/// esperando cada caso (neutro; ámbar pasadas 24 h) — es una cola que se
/// vacía, no un buzón.
class CaseQueue extends ConsumerStatefulWidget {
  const CaseQueue({super.key, required this.selectedId, required this.onOpen});

  final String? selectedId;
  final ValueChanged<DeskCase> onOpen;

  static const overdueAfter = Duration(hours: 24);

  @override
  ConsumerState<CaseQueue> createState() => _CaseQueueState();
}

class _CaseQueueState extends ConsumerState<CaseQueue> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(casesQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(casesQueryProvider.notifier).state = value.trim();
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(casesTabProvider);
    final waiting = ref.watch(waitingCountProvider).valueOrNull;
    final list = ref.watch(caseListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Semantics(
            header: true,
            child: const Text(
              'Casos',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          // Wrap: con letra grande del navegador las pestañas bajan de línea
          child: Wrap(
            runSpacing: 4,
            children: [
              for (final status in DeskCaseStatus.values)
                _TabButton(
                  key: Key('casesTab_${status.name}'),
                  label: switch (status) {
                    DeskCaseStatus.waiting => 'Esperando',
                    DeskCaseStatus.answered => 'Respondidos',
                    DeskCaseStatus.resolved => 'Resueltos',
                  },
                  count: status == DeskCaseStatus.waiting ? waiting : null,
                  selected: tab == status,
                  onTap: () => ref.read(casesTabProvider.notifier).state = status,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            key: const Key('casesSearch'),
            controller: _search,
            onChanged: _onSearch,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Número, correo, tienda o tema',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar búsqueda',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _search.clear();
                        _onSearch('');
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: list.when(
            skipLoadingOnRefresh: true,
            loading: () => const CasesSkeleton(),
            error: (e, _) => Align(
              alignment: Alignment.topLeft,
              child: CasesErrorBlock(message: e.toString(), onRetry: () => ref.invalidate(caseListProvider)),
            ),
            data: (state) => state.items.isEmpty
                ? _EmptyQueue(tab: tab, searching: ref.watch(casesQueryProvider).isNotEmpty)
                : ListView.separated(
                    key: const Key('casesList'),
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: state.items.length + (state.hasMore || state.moreError != null ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, i) {
                      if (i == state.items.length) return _MoreRow(state: state);
                      final c = state.items[i];
                      return _CaseRow(
                        supportCase: c,
                        selected: c.id == widget.selectedId,
                        now: ref.read(adminClockProvider)(),
                        onTap: () => widget.onOpen(c),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({super.key, required this.label, required this.selected, required this.onTap, this.count});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Semantics(
          selected: selected,
          button: true,
          child: Material(
            color: selected ? AdminColors.indigoSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  count == null ? label : '$label $count',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AdminColors.indigo : AppColors.onSurfaceMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _CaseRow extends StatelessWidget {
  const _CaseRow({required this.supportCase, required this.selected, required this.now, required this.onTap});
  final DeskCase supportCase;
  final bool selected;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = supportCase;
    final waiting = c.status == DeskCaseStatus.waiting;
    final waited = now.difference(c.lastMessageAt);
    final overdue = waiting && waited >= CaseQueue.overdueAfter;
    // La columna que manda (tesis del contrato): cuánto lleva esperando
    final span = now.difference(c.lastMessageAt);
    final when = span.inMinutes < 1 ? 'ahora' : adminSpan(span);
    final whenLabel = waiting ? 'espera' : 'hace';
    final preview = c.lastMessagePreview;

    return Material(
      color: selected ? AdminColors.indigoSoft : Colors.transparent,
      child: InkWell(
        key: Key('casesRow_${c.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Semantics(
                  label: '$whenLabel $when${overdue ? ', más de un día' : ''}',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        when,
                        key: Key('casesRowWhen_${c.id}'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: overdue ? FontWeight.w700 : FontWeight.w600,
                          color: overdue ? AdminColors.amber : AppColors.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          height: 1.25,
                        ),
                      ),
                      Text(
                        whenLabel,
                        style: TextStyle(fontSize: 12, color: overdue ? AdminColors.amber : AppColors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.fromApp ? c.storeLabel : 'Sin sesión · ${c.storeLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${c.number} · ${c.topicTitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurfaceMuted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (preview != null && preview.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        c.lastMessageBySupport == true ? 'Soporte: $preview' : preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.onSurface, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreRow extends ConsumerWidget {
  const _MoreRow({required this.state});
  final CaseListState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.moreError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(state.moreError!, style: const TextStyle(fontSize: 13, color: AppColors.error)),
              ),
            OutlinedButton(
              key: const Key('casesLoadMore'),
              onPressed: state.loadingMore ? null : () => ref.read(caseListProvider.notifier).loadMore(),
              child: Text(state.loadingMore ? 'Cargando…' : 'Cargar más (${state.items.length} de ${state.total})'),
            ),
          ],
        ),
      );
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.tab, required this.searching});
  final DeskCaseStatus tab;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final (String title, String hint) = searching
        ? ('Sin resultados', 'Prueba con el número del caso, el correo de quien escribió o el nombre de la tienda.')
        : switch (tab) {
            DeskCaseStatus.waiting => ('Sin casos esperando', 'Todo en orden: nadie espera respuesta de soporte.'),
            DeskCaseStatus.answered => ('Sin casos respondidos', 'Aquí quedan los casos a los que ya respondiste.'),
            DeskCaseStatus.resolved => ('Sin casos resueltos', 'Aquí quedan los casos cerrados.'),
          };
    return Padding(
      key: const Key('casesEmpty'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
          const SizedBox(height: 6),
          Text(hint, style: const TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.45)),
        ],
      ),
    );
  }
}
