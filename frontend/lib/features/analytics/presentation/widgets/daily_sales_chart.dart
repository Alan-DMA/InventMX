import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/analytics_dashboard.dart';

/// Barras de ventas por día — `CustomPainter` puro (Constitución Art. IV:
/// cero dependencias). Una barra por día del período; la de hoy en esmeralda,
/// el resto en gris; línea base y la cifra máxima como única marca de escala.
///
/// El pintor no dibuja texto de ejes: las etiquetas de fecha las pone el
/// widget en una fila debajo, con `Text` real (accesible y escalable).
class DailySalesChart extends StatelessWidget {
  const DailySalesChart({
    super.key,
    required this.points,
    required this.today,
    this.height = 140,
  });

  final List<DailySalesPoint> points;
  final DateTime today;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return SizedBox(height: height);

    final maxValue = points.fold<double>(0, (m, p) => p.revenueMxn > m ? p.revenueMxn : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Marca de escala: el mejor día, como dato — no como meta
        if (maxValue > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Mejor día: ${_mxn(maxValue)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.onSurfaceMuted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _DailyBarsPainter(
              points: points,
              maxValue: maxValue,
              today: today,
            ),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 6),
        _AxisLabels(points: points),
      ],
    );
  }
}

class _DailyBarsPainter extends CustomPainter {
  _DailyBarsPainter({
    required this.points,
    required this.maxValue,
    required this.today,
  });

  final List<DailySalesPoint> points;
  final double maxValue;
  final DateTime today;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    if (n == 0) return;

    final baseline = size.height - 1;
    final basePaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, baseline), Offset(size.width, baseline), basePaint);

    // Ancho de barra proporcional al número de días; hueco mínimo 2 px.
    final slot = size.width / n;
    final gap = n > 14 ? 2.0 : (n > 7 ? 4.0 : 8.0);
    final barWidth = (slot - gap).clamp(2.0, 40.0);
    final radius = Radius.circular(barWidth >= 8 ? 3 : 1.5);

    final todayDay = DateTime(today.year, today.month, today.day);
    final normalPaint = Paint()..color = AppColors.onSurfaceMuted.withValues(alpha: 0.45);
    final todayPaint = Paint()..color = AppColors.emerald;
    final emptyPaint = Paint()..color = AppColors.surfaceVariant;

    for (var i = 0; i < n; i++) {
      final p = points[i];
      final isToday = DateTime(p.date.year, p.date.month, p.date.day) == todayDay;
      final fraction = maxValue <= 0 ? 0.0 : p.revenueMxn / maxValue;
      // Un día en cero se marca con un tope de 2 px para que "no vendí" se vea
      // distinto de "no hay dato".
      final barHeight = fraction <= 0 ? 2.0 : (size.height - 4) * fraction;
      final left = i * slot + (slot - barWidth) / 2;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, baseline - barHeight, barWidth, barHeight),
        topLeft: radius,
        topRight: radius,
      );
      canvas.drawRRect(
        rect,
        fraction <= 0 ? emptyPaint : (isToday ? todayPaint : normalPaint),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DailyBarsPainter old) =>
      old.points != points || old.maxValue != maxValue || old.today != today;
}

/// Etiquetas de fecha: todas si son ≤ 7 días; si no, inicio · medio · fin.
class _AxisLabels extends StatelessWidget {
  const _AxisLabels({required this.points});
  final List<DailySalesPoint> points;

  static const _weekdays = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      color: AppColors.onSurfaceMuted,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    if (points.length <= 7) {
      return Row(
        children: [
          for (final p in points)
            Expanded(
              child: Text(
                points.length == 1 ? _dayMonth(p.date) : _weekdays[p.date.weekday - 1],
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
        ],
      );
    }

    final mid = points[points.length ~/ 2];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(_dayMonth(points.first.date), style: style),
        Text(_dayMonth(mid.date), style: style),
        Text(_dayMonth(points.last.date), style: style),
      ],
    );
  }
}

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String _dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String _mxn(double v) {
  final fixed = v.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return '\$$intPart.${parts[1]}';
}
