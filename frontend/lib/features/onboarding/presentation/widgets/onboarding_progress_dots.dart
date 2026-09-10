import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';

/// Indicador de pasos tipo dots + barra de progreso lineal.
/// Replica la referencia visual: chip de paso + LinearProgressIndicator + porcentaje.
class OnboardingProgressIndicator extends StatelessWidget {
  const OnboardingProgressIndicator({
    super.key,
    required this.currentStep, // 0-based
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  double get _progress => (currentStep + 1) / totalSteps;
  String get _label => 'PASO ${currentStep + 1} DE $totalSteps';
  String get _percent => '${((_progress) * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Chip de paso
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.flag_rounded,
                    size: 12,
                    color: AppColors.emerald,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.emerald,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              _percent,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _progress,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.emerald),
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}
