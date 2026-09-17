import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/subscription.dart';

/// La línea del ciclo — Tarea 14.2 (dirección "Línea del ciclo").
///
/// El mes como una barra con tres tramos: periodo activo (esmeralda hasta el
/// vencimiento), ventana de solo lectura (ámbar, días 1–10) y bloqueo total
/// (rojo, día 11+). "Hoy" es un marcador que se mueve sobre ella. Debajo,
/// las fechas exactas: el tendero nunca es sorprendido por un estado que ya
/// vio venir (Constitución Art. VI §6.3, sin urgencia fabricada).
///
/// `compact` es la versión de una línea que vive en el banner de Soft Lock.
class CycleLine extends StatelessWidget {
  const CycleLine({
    super.key,
    required this.dueDate,
    required this.status,
    this.now,
    this.compact = false,
  });

  final DateTime dueDate;
  final SubscriptionStatus status;
  final DateTime? now;
  final bool compact;

  static const softLockDays = 10;
  static const _tailDays = 4; // aire después del bloqueo para que se lea

  @override
  Widget build(BuildContext context) {
    final today = _day(now ?? DateTime.now());
    final due = _day(dueDate);
    final softAt = due.add(const Duration(days: 1));
    final hardAt = due.add(const Duration(days: softLockDays + 1));
    final start = due.subtract(const Duration(days: 30));
    final end = hardAt.add(const Duration(days: _tailDays));
    final total = end.difference(start).inDays.toDouble();

    double pos(DateTime d) =>
        (d.difference(start).inDays / total).clamp(0.0, 1.0);

    final dueFrac = pos(due);
    final hardFrac = pos(hardAt);
    final todayFrac = pos(today);
    final daysToDue = due.difference(today).inDays;

    final barHeight = compact ? 4.0 : 6.0;

    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // Al aprobar un pago el vencimiento salta un periodo: el tramo activo
        // se extiende animado hasta la fecha nueva en vez de saltar.
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: dueFrac, end: dueFrac),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, animatedDue, _) => _paintBar(
            w: w,
            dueFrac: animatedDue,
            hardFrac: (animatedDue + (hardFrac - dueFrac)).clamp(0.0, 1.0),
            todayFrac: todayFrac,
            barHeight: barHeight,
          ),
        );
      },
    );

    if (compact) return bar;

    final statusColor = switch (status) {
      SubscriptionStatus.active => AppColors.emerald,
      SubscriptionStatus.softLock => AppColors.warning,
      SubscriptionStatus.hardLock => AppColors.error,
    };

    final headline = switch (status) {
      SubscriptionStatus.active when daysToDue > 1 =>
        'Vence el ${shortDate(due)} · faltan $daysToDue días',
      SubscriptionStatus.active when daysToDue == 1 =>
        'Vence mañana, ${shortDate(due)}',
      SubscriptionStatus.active when daysToDue == 0 =>
        'Vence hoy, ${shortDate(due)}',
      SubscriptionStatus.active => 'Venció el ${shortDate(due)}',
      SubscriptionStatus.softLock =>
        'Solo lectura · día ${-daysToDue} de $softLockDays',
      SubscriptionStatus.hardLock => 'Bloqueada desde el ${shortDate(hardAt)}',
    };
    return _withLegend(bar, due, softAt, hardAt, statusColor, headline);
  }

  Widget _paintBar({
    required double w,
    required double dueFrac,
    required double hardFrac,
    required double todayFrac,
    required double barHeight,
  }) {
    return SizedBox(
      height: compact ? 14 : 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Base: el mes completo
          Positioned(
            left: 0,
            right: 0,
            top: (compact ? 14 : 22) / 2 - barHeight / 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(barHeight),
              child: SizedBox(
                height: barHeight,
                child: Row(
                  // Sin stretch los ColoredBox miden 0 de alto y la barra no se pinta.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: (dueFrac * 1000).round(),
                      child: const ColoredBox(color: AppColors.emerald),
                    ),
                    Expanded(
                      flex: ((hardFrac - dueFrac) * 1000).round(),
                      child: const ColoredBox(color: AppColors.warning),
                    ),
                    Expanded(
                      flex: ((1 - hardFrac) * 1000).round().clamp(1, 1000),
                      child: const ColoredBox(color: AppColors.error),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Marcador de vencimiento
          _tick(w * dueFrac, compact ? 14 : 22, AppColors.onSurface),
          // Hoy
          Positioned(
            // Nunca fuera de la barra: un moroso de 20 días sigue viéndose.
            left: ((w * todayFrac) - (compact ? 5 : 7))
                .clamp(0.0, w - (compact ? 10 : 14)),
            top: 0,
            child: Semantics(
              label: 'Hoy',
              child: Container(
                key: const Key('cycleLineToday'),
                width: compact ? 10 : 14,
                height: compact ? 14 : 22,
                decoration: BoxDecoration(
                  color: AppColors.darkSlate,
                  borderRadius: BorderRadius.circular(compact ? 5 : 7),
                  border: Border.all(color: AppColors.onSurface, width: 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _withLegend(Widget bar, DateTime due, DateTime softAt, DateTime hardAt,
      Color statusColor, String headline) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              periodLabel(due),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.onSurfaceMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                headline,
                key: const Key('cycleLineHeadline'),
                textAlign: TextAlign.end,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        bar,
        const SizedBox(height: 8),
        // Wrap: cada fecha salta de línea completa, nunca partida ("1 / oct").
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _legend(AppColors.emerald, 'Activa hasta el ${shortDate(due)}'),
            _legend(AppColors.warning, 'Solo lectura ${shortDate(softAt)}'),
            _legend(AppColors.error, 'Bloqueo ${shortDate(hardAt)}'),
          ],
        ),
      ],
    );
  }

  Widget _tick(double x, double h, Color color) => Positioned(
        left: x - 1,
        top: 0,
        child: Container(width: 2, height: h, color: color),
      );

  Widget _legend(Color color, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            softWrap: false,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.onSurfaceMuted,
              height: 1.2,
            ),
          ),
        ],
      );

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}
