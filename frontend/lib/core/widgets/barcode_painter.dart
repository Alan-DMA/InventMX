import 'dart:math' as math show Random;
import 'package:flutter/material.dart';

/// Código de barras estilo Code128 (representación visual, no escaneable).
///
/// Extraído de `product_label_modal.dart` (Tarea 5.2) para reutilizarlo en la
/// referencia de pago OXXO (Tarea 14.2). Determinista por `code`: el mismo
/// texto siempre pinta las mismas barras. Constitución Art. IV: sin paquete.
class BarcodePainter extends CustomPainter {
  const BarcodePainter({required this.code, required this.color});

  final String code;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final rng = math.Random(
      code.codeUnits.fold<int>(0, (a, b) => a + b),
    );

    const barCount = 60;
    final totalWidth = size.width;
    double x = 0;

    for (int i = 0; i < barCount; i++) {
      final isBar = i.isEven;
      final widthFactor = (rng.nextInt(4) + 1).toDouble();
      final barW = (totalWidth / barCount) * widthFactor * 0.6;

      if (isBar) {
        canvas.drawRect(
            Rect.fromLTWH(x, 0, barW.clamp(1, barW), size.height), paint);
      }
      x += barW;
      if (x >= totalWidth) break;
    }
  }

  @override
  bool shouldRepaint(BarcodePainter old) =>
      old.code != code || old.color != color;
}
