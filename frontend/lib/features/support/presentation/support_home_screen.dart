import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/support_models.dart';
import 'support_provider.dart';
import 'widgets/support_cases_sheet.dart';
import 'widgets/support_widgets.dart';

/// Soporte (Centro de soporte, P23): "¿En qué te ayudamos?" con los temas como
/// renglones de lista. "Mis casos" vive en el ícono de la barra (siempre
/// visible, con insignia de respuestas nuevas) y se abre como hoja inferior.
///
/// Surface brief `ort-presentation-support-home-screen-dart-c596d13c`: la
/// ayuda antes que el formulario, y el caso como una conversación.
class SupportHomeScreen extends ConsumerStatefulWidget {
  const SupportHomeScreen({super.key});

  @override
  ConsumerState<SupportHomeScreen> createState() => _SupportHomeScreenState();
}

class _SupportHomeScreenState extends ConsumerState<SupportHomeScreen> {
  Future<void> _refresh() async {
    ref.invalidate(supportCasesProvider);
    ref.invalidate(supportTopicsProvider);
    ref.invalidate(supportUnreadProvider);
    await ref.read(supportTopicsProvider.future);
  }

  Future<void> _openCases() async {
    final picked = await showSupportCasesSheet(context);
    if (picked == null || !mounted) return;
    await context.push(AppRoutes.supportCasePath(picked.id));
    ref.invalidate(supportCasesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final topicsAsync = ref.watch(supportTopicsProvider);
    // La insignia sale de la misma lista que muestra la hoja: el número del
    // ícono coincide siempre con los puntos azules de adentro.
    final cases = ref.watch(supportCasesProvider).valueOrNull ?? const <SupportCase>[];
    final unread = cases.where((c) => c.unread).length;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        title: const Text('Soporte'),
        actions: [
          IconButton(
            key: const Key('supportCasesButton'),
            tooltip: switch (unread) {
              0 => 'Mis casos',
              1 => 'Mis casos · 1 respuesta nueva',
              _ => 'Mis casos · $unread respuestas nuevas',
            },
            onPressed: _openCases,
            icon: Badge(
              key: const Key('supportCasesBadge'),
              isLabelVisible: unread > 0,
              label: Text(unread > 9 ? '9+' : '$unread'),
              backgroundColor: AppColors.skyBlue,
              textColor: AppColors.darkSlate,
              child: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.onSurface),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: topicsAsync.when(
        loading: () => const SupportSkeleton(),
        error: (e, _) => SupportErrorState(
          message: errorText(e, 'No pudimos cargar la ayuda.'),
          onRetry: () => ref.invalidate(supportTopicsProvider),
        ),
        data: (topics) => RefreshIndicator(
          color: AppColors.emerald,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SupportSectionTitle('¿En qué te ayudamos?'),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Elige lo que se parece a tu problema. Primero te decimos cómo resolverlo; si no alcanza, '
                  'nos escribes desde ahí.',
                  style: TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4),
                ),
              ),
              for (var i = 0; i < topics.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 20, color: AppColors.border),
                TopicRow(
                  key: Key('supportTopic_${topics[i].key}'),
                  topic: topics[i],
                  onTap: () => context.push(AppRoutes.supportTopicPath(topics[i].key)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
