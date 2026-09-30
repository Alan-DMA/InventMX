import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/support_models.dart';
import '../support_provider.dart';
import 'support_widgets.dart';

/// "Mis casos" como hoja inferior desde el ícono de la barra de Soporte (QA de
/// Eduardo, Sep 29: la sección empujaba "¿En qué te ayudamos?"). Devuelve el
/// caso tocado; quien la abre navega a su seguimiento.
///
/// Sin `DraggableScrollableSheet` (QA de Eduardo en el detalle de proveedor):
/// alto máximo, "X" explícita y la lista se desplaza por dentro.
Future<SupportCase?> showSupportCasesSheet(BuildContext context) => showModalBottomSheet<SupportCase>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const SupportCasesSheet(),
    );

/// Sin leer primero; luego los abiertos antes que los resueltos; dentro de
/// cada grupo, lo más reciente.
List<SupportCase> orderCases(List<SupportCase> cases) => [...cases]..sort((a, b) {
    if (a.unread != b.unread) return a.unread ? -1 : 1;
    final aDone = a.status == CaseStatus.resolved;
    final bDone = b.status == CaseStatus.resolved;
    if (aDone != bDone) return aDone ? 1 : -1;
    return b.lastMessageAt.compareTo(a.lastMessageAt);
  });

/// "1 respuesta nueva · 2 esperando a soporte · 3 resueltos": cada caso cuenta
/// una sola vez (lo no leído gana) y los conteos en cero no se escriben.
String casesSummary(List<SupportCase> cases) {
  var fresh = 0, answered = 0, waiting = 0, resolved = 0;
  for (final c in cases) {
    if (c.unread) {
      fresh++;
    } else {
      switch (c.status) {
        case CaseStatus.answered:
          answered++;
        case CaseStatus.waitingSupport:
          waiting++;
        case CaseStatus.resolved:
          resolved++;
      }
    }
  }
  String n(int count, String one, String many) => '$count ${count == 1 ? one : many}';
  return [
    if (fresh > 0) n(fresh, 'respuesta nueva', 'respuestas nuevas'),
    if (answered > 0) n(answered, 'respondido', 'respondidos'),
    if (waiting > 0) '$waiting esperando a soporte',
    if (resolved > 0) n(resolved, 'resuelto', 'resueltos'),
  ].join(' · ');
}

class SupportCasesSheet extends ConsumerWidget {
  const SupportCasesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supportCasesProvider);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          key: const Key('supportCasesSheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.onSurfaceMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Mis casos',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                    ),
                  ),
                  IconButton(
                    key: const Key('supportCasesClose'),
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close_rounded, color: AppColors.onSurfaceMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: async.when(
                loading: () => const _Loading(),
                error: (e, _) => SupportErrorState(
                  message: errorText(e, 'No pudimos cargar tus casos.'),
                  onRetry: () {
                    ref.invalidate(supportCasesProvider);
                    ref.invalidate(supportUnreadProvider);
                  },
                ),
                data: (cases) => cases.isEmpty ? const _Empty() : _CaseList(cases: orderCases(cases)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaseList extends StatelessWidget {
  const _CaseList({required this.cases});
  final List<SupportCase> cases;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              casesSummary(cases),
              key: const Key('supportCasesSummary'),
              style: const TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: cases.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 34, color: AppColors.border),
              itemBuilder: (context, i) => CaseRow(
                supportCase: cases[i],
                onTap: () => Navigator.of(context).pop(cases[i]),
              ),
            ),
          ),
        ],
      );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Cargando tus casos',
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: SizedBox(
              key: Key('supportCasesLoading'),
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.emerald),
            ),
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Padding(
        key: Key('supportCasesEmpty'),
        padding: EdgeInsets.fromLTRB(32, 24, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 32, color: AppColors.onSurfaceMuted),
            SizedBox(height: 12),
            Text(
              'Aún no tienes casos',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.onSurface),
            ),
            SizedBox(height: 6),
            Text(
              'Cuando escribas a soporte desde un tema, aquí verás tu caso y la respuesta.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4),
            ),
          ],
        ),
      );
}

/// Un caso: número y tema, estado escrito, autor si no es tuyo y cuándo. La
/// respuesta sin leer lleva punto azul cielo y negritas.
class CaseRow extends StatelessWidget {
  const CaseRow({super.key, required this.supportCase, required this.onTap});
  final SupportCase supportCase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = supportCase;
    return InkWell(
      key: Key('supportCase_${c.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
        child: Row(
          children: [
            // Punto de "respuesta sin leer": acompaña a las negritas, no las sustituye
            SizedBox(
              width: 14,
              child: c.unread
                  ? Semantics(
                      label: 'Respuesta nueva de soporte',
                      child: Container(
                        key: const Key('supportCaseUnreadDot'),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: AppColors.skyBlue, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Caso ${c.number} · ${c.topicTitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: c.unread ? FontWeight.w700 : FontWeight.w500,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      CaseStatusChip(c.status),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          [
                            if (!c.isMine && c.authorName != null) c.authorName!,
                            caseMoment(c.lastMessageAt),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceMuted),
          ],
        ),
      ),
    );
  }
}
