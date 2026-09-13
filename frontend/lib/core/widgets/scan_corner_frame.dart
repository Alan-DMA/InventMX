import 'package:flutter/material.dart';

/// Marco de 4 esquinas con pulso, usado sobre las vistas de cámara en vivo.
///
/// Nació en `GondolaScanScreen` (Tarea 5.2) y se extrajo aquí al reutilizarlo
/// en la captura de facturas (12.2): el color comunica el estado del escaneo
/// —ámbar mientras algo falta, verde cuando ya se puede disparar— y el pulso
/// dice que la cámara está viva aunque la imagen no cambie.
class ScanCornerFrame extends StatefulWidget {
  const ScanCornerFrame({
    super.key,
    required this.color,
    this.size = const Size(240, 120),
    this.animate = true,
  });

  final Color color;
  final Size size;

  /// Se apaga en tests y con "reducir movimiento" del sistema.
  final bool animate;

  @override
  State<ScanCornerFrame> createState() => _ScanCornerFrameState();
}

class _ScanCornerFrameState extends State<ScanCornerFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final Animation<double> _pulse = Tween<double>(
    begin: 0.85,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(ScanCornerFrame old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.animate && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = CustomPaint(
      size: widget.size,
      painter: _CornerPainter(color: widget.color),
    );

    if (!widget.animate) return frame;
    return ScaleTransition(scale: _pulse, child: frame);
  }
}

/// Dibuja las 4 esquinas del marco de escaneo.
class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLen = 28.0;
    const r = 8.0;

    final w = size.width;
    final h = size.height;

    // Superior-izquierda
    canvas.drawLine(const Offset(r, 0), const Offset(cornerLen, 0), paint);
    canvas.drawLine(const Offset(0, r), const Offset(0, cornerLen), paint);
    canvas.drawArc(
        const Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14, -1.57, false, paint);

    // Superior-derecha
    canvas.drawLine(Offset(w - cornerLen, 0), Offset(w - r, 0), paint);
    canvas.drawLine(Offset(w, r), Offset(w, cornerLen), paint);
    canvas.drawArc(
        Rect.fromLTWH(w - r * 2, 0, r * 2, r * 2), 4.71, -1.57, false, paint);

    // Inferior-izquierda
    canvas.drawLine(Offset(0, h - cornerLen), Offset(0, h - r), paint);
    canvas.drawLine(Offset(r, h), Offset(cornerLen, h), paint);
    canvas.drawArc(
        Rect.fromLTWH(0, h - r * 2, r * 2, r * 2), 1.57, -1.57, false, paint);

    // Inferior-derecha
    canvas.drawLine(Offset(w, h - cornerLen), Offset(w, h - r), paint);
    canvas.drawLine(Offset(w - cornerLen, h), Offset(w - r, h), paint);
    canvas.drawArc(Rect.fromLTWH(w - r * 2, h - r * 2, r * 2, r * 2), 0, -1.57,
        false, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}
