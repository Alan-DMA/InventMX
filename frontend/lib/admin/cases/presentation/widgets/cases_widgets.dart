import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../core/admin_colors.dart';
import '../../domain/desk_case.dart';

/// Estado del caso, escrito (nunca sólo color). Esperando = neutro, y ámbar
/// si ya pasó más de un día (`overdue`); Respondido = azul cielo (le toca al
/// tendero); Resuelto = apagado. El índigo queda sólo para la plataforma.
class DeskStatusChip extends StatelessWidget {
  const DeskStatusChip(this.status, {super.key, this.overdue = false});
  final DeskCaseStatus status;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final (Color fg, IconData icon) = switch (status) {
      DeskCaseStatus.waiting => (overdue ? AdminColors.amber : AppColors.onSurface, Icons.schedule_rounded),
      DeskCaseStatus.answered => (AppColors.skyBlue, Icons.forum_outlined),
      DeskCaseStatus.resolved => (AppColors.onSurfaceMuted, Icons.check_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status == DeskCaseStatus.resolved ? Colors.transparent : fg.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: status == DeskCaseStatus.resolved ? Border.all(color: AppColors.border) : null,
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

/// Algo falló: el mensaje y "Reintentar", en su lugar.
class CasesErrorBlock extends StatelessWidget {
  const CasesErrorBlock({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 22, color: AppColors.onSurfaceMuted),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(fontSize: 14, color: AppColors.onSurface, height: 1.45)),
            const SizedBox(height: 14),
            OutlinedButton(key: const Key('casesRetry'), onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      );
}

/// Bloques del tamaño de lo que viene (sin girar nada).
class CasesSkeleton extends StatelessWidget {
  const CasesSkeleton({super.key, this.rows = 6});
  final int rows;

  @override
  Widget build(BuildContext context) => Column(
        key: const Key('casesSkeleton'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(180 + (i % 3) * 30.0, 13),
                  const SizedBox(height: 8),
                  _bar(250, 11),
                ],
              ),
            ),
        ],
      );

  static Widget _bar(double width, double height) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
      );
}
