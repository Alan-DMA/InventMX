import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/capture_quality.dart';

/// Banda de instrucción sobre la vista de cámara.
///
/// Dice **qué mover**, no qué falló: el usuario está de pie frente al
/// repartidor y no le sirve un diagnóstico técnico. El color repite lo que ya
/// dice el texto (ámbar = falta algo, verde = listo) para que el estado se lea
/// también en una pantalla con reflejo donde el color se distingue mal.
class CaptureGuidance extends StatelessWidget {
  const CaptureGuidance({
    super.key,
    required this.assessment,
    required this.isReady,
  });

  /// Nulo mientras llega el primer cuadro analizado.
  final CaptureAssessment? assessment;

  /// Verde solo cuando además de estar bien, se mantuvo estable varios cuadros.
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final current = assessment;
    final color = isReady ? AppColors.emerald : AppColors.warning;
    final message = current?.message ?? 'Enfocando la factura…';

    return Container(
      key: const Key('captureGuidance'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkSlate.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReady
                ? Icons.check_circle_outline_rounded
                : Icons.center_focus_weak_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
