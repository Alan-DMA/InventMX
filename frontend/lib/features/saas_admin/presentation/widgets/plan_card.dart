import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/subscription.dart';

/// Tarjeta compacta de plan — Tarea 14.2.1.
///
/// El plan actual siempre es el seleccionado (nunca "el más caro por
/// defecto"); cambiar es una acción explícita que muestra el nuevo monto.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.isCurrent,
    required this.onSelect,
    this.busy = false,
  });

  final SaasPlan plan;
  final bool isCurrent;
  final VoidCallback? onSelect;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isCurrent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          plan.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.emerald.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Tu plan',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.emerald,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${plan.highlights.isEmpty ? '' : '${plan.highlights} · '}'
                    'hasta ${plan.maxUsers} usuarios',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceMuted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  mxn(plan.priceMxn),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const Text(
                  '/ mes',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
                ),
              ],
            ),
            if (!isCurrent) ...[
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  key: Key('selectPlan-${plan.id}'),
                  onPressed: busy ? null : onSelect,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.onSurface,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Elegir', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
