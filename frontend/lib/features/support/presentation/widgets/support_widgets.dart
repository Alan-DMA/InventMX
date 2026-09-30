import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/support_models.dart';

/// Estado del caso, **escrito** (nunca sólo color): Esperando a soporte
/// (neutro), Respondido (azul cielo: te toca a ti) y Resuelto (apagado).
class CaseStatusChip extends StatelessWidget {
  const CaseStatusChip(this.status, {super.key});
  final CaseStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, IconData icon) = switch (status) {
      CaseStatus.waitingSupport => (AppColors.onSurface, AppColors.surfaceVariant, Icons.schedule_rounded),
      CaseStatus.answered => (AppColors.skyBlue, AppColors.skyBlue.withValues(alpha: 0.14), Icons.forum_outlined),
      CaseStatus.resolved => (AppColors.onSurfaceMuted, AppColors.surface, Icons.check_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: status == CaseStatus.resolved ? Border.all(color: AppColors.border) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(status.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

/// Título de sección de la pantalla de Soporte.
class SupportSectionTitle extends StatelessWidget {
  const SupportSectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 12, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.onSurface),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Un tema como renglón de lista: su título con las palabras del tendero y
/// una línea de resumen. Sin tarjeta ni ícono decorativo (brief de Soporte).
class TopicRow extends StatelessWidget {
  const TopicRow({super.key, required this.topic, required this.onTap});
  final HelpTopic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic.title,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                      ),
                      if (topic.summary.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          topic.summary,
                          style: const TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceMuted),
              ],
            ),
          ),
        ),
      );
}

/// Esqueleto mientras carga: bloques del tamaño de lo que viene, sin spinner.
class SupportSkeleton extends StatelessWidget {
  const SupportSkeleton({super.key, this.rows = 5});
  final int rows;

  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: 18),
        itemBuilder: (_, i) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bar(width: 200 + (i % 3) * 30.0, height: 14),
            const SizedBox(height: 8),
            _bar(width: 260, height: 11),
          ],
        ),
      );

  static Widget _bar({required double width, required double height}) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
      );
}

/// Algo falló: el mensaje del servidor y "Reintentar".
class SupportErrorState extends StatelessWidget {
  const SupportErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 32, color: AppColors.onSurfaceMuted),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14.5, color: AppColors.onSurface, height: 1.4),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                key: const Key('supportRetry'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
}

String errorText(Object error, String fallback) {
  final text = error.toString();
  return text.startsWith('Exception') || text.isEmpty ? fallback : text;
}
