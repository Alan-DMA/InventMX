import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/subscription.dart';

/// La línea del ciclo — dirección "Línea del ciclo" (Tarea 14.2), adaptada al
/// modelo prepago (P9–P13, Sep 2026).
///
/// El mes como una barra con tres tramos: vigente (esmeralda hasta el
/// vencimiento), gracia con **acceso completo** (ámbar, 10 días — P10) y
/// suspensión (rojo). "Hoy" es un marcador que se mueve sobre ella. Debajo,
/// las fechas exactas: el tendero nunca es sorprendido por un estado que ya
/// vio venir (sin urgencia fabricada).
///
/// `compact` es la versión de una línea que vive en el banner.
class CycleLine extends StatelessWidget {
  const CycleLine({
    super.key,
    required this.paidUntil,
    required this.graceUntil,
    required this.entitlement,
    this.now,
    this.compact = false,
  });

  final DateTime paidUntil;
  final DateTime graceUntil;
  final Entitlement entitlement;
  final DateTime? now;
  final bool compact;

  static const _tailDays = 4; // aire después de la suspensión para que se lea

  @override
  Widget build(BuildContext context) {
    final today = _day(now ?? DateTime.now());
    final due = _day(paidUntil);
    final graceEnd = _day(graceUntil);
    final start = addMonths(due, -1);
    final end = graceEnd.add(const Duration(days: _tailDays));
    final total = end.difference(start).inDays.toDouble();

    double pos(DateTime d) =>
        (d.difference(start).inDays / total).clamp(0.0, 1.0);

    final dueFrac = pos(due);
    final graceFrac = pos(graceEnd);
    final todayFrac = pos(today);
    final daysToDue = due.difference(today).inDays;
    final graceLeft = graceEnd.difference(today).inDays;

    final barHeight = compact ? 4.0 : 6.0;

    final bar = LayoutBuilder(
      builder: (context, constraints) => _paintBar(
        w: constraints.maxWidth,
        dueFrac: dueFrac,
        graceFrac: graceFrac,
        todayFrac: todayFrac,
        barHeight: barHeight,
      ),
    );

    if (compact) return bar;

    final statusColor = switch (entitlement) {
      Entitlement.gracia => AppColors.warning,
      Entitlement.vencida => AppColors.error,
      _ => AppColors.emerald,
    };

    final headline = switch (entitlement) {
      Entitlement.gracia when graceLeft > 1 =>
        'En gracia · $graceLeft días con acceso completo',
      Entitlement.gracia => 'Último día de gracia',
      Entitlement.vencida => 'Suspendida desde el ${shortDate(graceEnd)}',
      _ when daysToDue > 1 =>
        'Vence el ${shortDate(due)} · faltan $daysToDue días',
      _ when daysToDue == 1 => 'Vence mañana, ${shortDate(due)}',
      _ => 'Vence hoy, ${shortDate(due)}',
    };
    return _withLegend(bar, due, graceEnd, statusColor, headline);
  }

  Widget _paintBar({
    required double w,
    required double dueFrac,
    required double graceFrac,
    required double todayFrac,
    required double barHeight,
  }) {
    final height = compact ? 14.0 : 22.0;
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Base: el mes completo
          Positioned(
            left: 0,
            right: 0,
            top: height / 2 - barHeight / 2,
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
                      flex: ((graceFrac - dueFrac) * 1000).round(),
                      child: const ColoredBox(color: AppColors.warning),
                    ),
                    Expanded(
                      flex: ((1 - graceFrac) * 1000).round().clamp(1, 1000),
                      child: const ColoredBox(color: AppColors.error),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Marcador de vencimiento
          Positioned(
            left: w * dueFrac - 1,
            top: 0,
            child: Container(width: 2, height: height, color: AppColors.onSurface),
          ),
          // Hoy — nunca fuera de la barra: un suspendido hace 20 días sigue viéndose
          Positioned(
            left: ((w * todayFrac) - (compact ? 5 : 7))
                .clamp(0.0, w - (compact ? 10 : 14)),
            top: 0,
            child: Semantics(
              label: 'Hoy',
              child: Container(
                key: const Key('cycleLineToday'),
                width: compact ? 10 : 14,
                height: height,
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

  Widget _withLegend(Widget bar, DateTime due, DateTime graceEnd,
      Color statusColor, String headline) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              periodLabel(due),
              style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
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
            _legend(AppColors.emerald, 'Vigente hasta el ${shortDate(due)}'),
            _legend(AppColors.warning, 'Gracia hasta el ${shortDate(graceEnd)}'),
            _legend(AppColors.error,
                'Suspensión el ${shortDate(graceEnd.add(const Duration(days: 1)))}'),
          ],
        ),
      ],
    );
  }

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
                fontSize: 11.5, color: AppColors.onSurfaceMuted, height: 1.2),
          ),
        ],
      );

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}
