import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../purchases_provider.dart';

/// Chips "Todas / Pendientes / Recibidas" con badge numérico — Figma nodo
/// `1:21`. Adapta la estructura del diseño (chip oscuro seleccionado + badge
/// de conteo) a `AppColors` en vez de la paleta clara del Figma referencial.
class PurchaseStatusChipBar extends StatelessWidget {
  const PurchaseStatusChipBar({
    super.key,
    required this.state,
    required this.onSelected,
  });

  final PurchaseOrdersState state;
  final ValueChanged<PurchaseChipFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Chip(
          label: 'Todas',
          count: state.allCount,
          isSelected: state.chipFilter == PurchaseChipFilter.all,
          onTap: () => onSelected(PurchaseChipFilter.all),
        ),
        const SizedBox(width: 8),
        _Chip(
          label: 'Pendientes',
          count: state.pendingCount,
          isSelected: state.chipFilter == PurchaseChipFilter.pending,
          badgeColor: AppColors.warning,
          onTap: () => onSelected(PurchaseChipFilter.pending),
        ),
        const SizedBox(width: 8),
        _Chip(
          label: 'Recibidas',
          count: state.receivedCount,
          isSelected: state.chipFilter == PurchaseChipFilter.received,
          badgeColor: AppColors.success,
          onTap: () => onSelected(PurchaseChipFilter.received),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
    this.badgeColor,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.onSurface : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.onSurface : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? AppColors.darkSlate : AppColors.onSurfaceMuted,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.darkSlate.withValues(alpha: 0.15)
                    : (badgeColor ?? AppColors.onSurfaceMuted).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? AppColors.darkSlate : (badgeColor ?? AppColors.onSurfaceMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
