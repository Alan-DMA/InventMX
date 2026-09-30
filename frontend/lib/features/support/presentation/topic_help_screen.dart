import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../account/presentation/account_provider.dart';
import '../../management/presentation/management_provider.dart';
import '../domain/support_models.dart';
import 'support_provider.dart';
import 'widgets/support_widgets.dart';

/// La ayuda de un tema, antes del formulario (P23): se lee como un artículo
/// corto, con la acción que lo resuelve cuando existe, y al final "Aún
/// necesito ayuda" siempre visible y con peso (esconderlo sería Obstrucción).
///
/// `public`: quien no puede entrar (P24). Sin `topicKey` muestra el primer
/// tema público, o la lista si el servidor ofrece varios.
class TopicHelpScreen extends ConsumerWidget {
  const TopicHelpScreen({super.key, this.topicKey, this.public = false});

  final String? topicKey;
  final bool public;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topicsAsync = ref.watch(public ? publicTopicsProvider : supportTopicsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        title: Text(public ? 'Ayuda' : 'Soporte'),
      ),
      body: topicsAsync.when(
        loading: () => const SupportSkeleton(rows: 4),
        error: (e, _) => SupportErrorState(
          message: errorText(e, 'No pudimos cargar la ayuda.'),
          onRetry: () => ref.invalidate(public ? publicTopicsProvider : supportTopicsProvider),
        ),
        data: (topics) {
          final HelpTopic? topic = topicKey != null
              ? topics.where((t) => t.key == topicKey).firstOrNull
              : (topics.length == 1 ? topics.first : null);
          if (topic == null && topicKey == null && topics.length > 1) {
            return ListView(
              children: [
                for (final t in topics)
                  TopicRow(topic: t, onTap: () => context.push('${AppRoutes.publicHelp}?tema=${t.key}')),
              ],
            );
          }
          if (topic == null) {
            return SupportErrorState(
              message: 'Este tema ya no está disponible.',
              onRetry: () => ref.invalidate(public ? publicTopicsProvider : supportTopicsProvider),
            );
          }
          return _Article(topic: topic, public: public);
        },
      ),
    );
  }
}

class _Article extends ConsumerWidget {
  const _Article({required this.topic, required this.public});
  final HelpTopic topic;
  final bool public;

  /// Qué pantalla abre cada `target` del servidor y si este usuario puede
  /// llegar a ella. Lo que no se conoce o no se puede, no se ofrece.
  String? _routeFor(WidgetRef ref, String target) {
    if (public) return target == 'forgot_password' ? AppRoutes.recover : null;
    return switch (target) {
      'subscription' => ref.watch(canSeeSubscriptionProvider) ? AppRoutes.subscription : null,
      'manage_members' => ref.watch(canManageMembersProvider) ? AppRoutes.manageMembers : null,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      for (final a in topic.actions)
        if (_routeFor(ref, a.target) case final route?) (a.label, route),
    ];
    const bodyStyle = TextStyle(fontSize: 15.5, color: AppColors.onSurface, height: 1.55);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          topic.title,
          key: const Key('topicTitle'),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.onSurface, height: 1.2),
        ),
        const SizedBox(height: 16),
        for (final block in topic.blocks) ...[
          if (block.isList)
            for (final bullet in block.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 9, right: 12),
                      child: SizedBox(
                        width: 6,
                        height: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: AppColors.onSurfaceMuted, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                    Expanded(child: Text(bullet, style: bodyStyle)),
                  ],
                ),
              )
          else
            Text(block.text, style: bodyStyle),
          const SizedBox(height: 14),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 4),
          for (final (label, route) in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                key: Key('topicAction_$route'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: AppColors.onSurface,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => context.push(route),
                child: Text(label),
              ),
            ),
        ],
        const SizedBox(height: 20),
        const Divider(color: AppColors.border),
        const SizedBox(height: 16),
        const Text(
          '¿No se resolvió?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          public
              ? 'Cuéntanos qué pasa y te respondemos por correo.'
              : 'Cuéntanos qué pasa y te respondemos aquí mismo, en la app.',
          style: const TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted, height: 1.4),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            key: const Key('topicNeedHelp'),
            onPressed: () => context.push(
              public
                  ? '${AppRoutes.publicHelpForm}?tema=${topic.key}'
                  : AppRoutes.supportTopicFormPath(topic.key),
            ),
            child: const Text('Aún necesito ayuda'),
          ),
        ),
      ],
    );
  }
}
