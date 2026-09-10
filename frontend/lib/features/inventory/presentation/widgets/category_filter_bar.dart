import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_colors.dart';

/// Barra horizontal de chips de filtro.
///
/// Chips:
///   [Todos]  [Categoría 1]  [Categoría 2]  ...  [⚠ Stock bajo]
///
/// - "Todos" limpia el filtro de categoría (activeCategory == null)
/// - "⚠ Stock bajo" es independiente y llama a onToggleLowStock
/// - Las categorías se construyen dinámicamente desde la lista recibida
class CategoryFilterBar extends StatelessWidget {
  const CategoryFilterBar({
    super.key,
    required this.categories,
    required this.activeCategory,
    required this.showLowStock,
    required this.onCategorySelected,
    required this.onToggleLowStock,
  });

  final List<String> categories;
  final String? activeCategory;
  final bool showLowStock;
  final ValueChanged<String?> onCategorySelected;
  final VoidCallback onToggleLowStock;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Chip "Todos"
          _FilterChip(
            label: 'Todos',
            isSelected: activeCategory == null && !showLowStock,
            onTap: () {
              onCategorySelected(null);
              if (showLowStock) onToggleLowStock();
            },
          ),
          const SizedBox(width: 8),

          // Chips de categoría dinámicos
          ...categories.map((cat) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FilterChip(
                label: cat,
                isSelected: activeCategory == cat,
                onTap: () => onCategorySelected(cat),
              ),
            );
          }),

          // Chip "⚠ Stock bajo"
          _FilterChip(
            label: '⚠ Stock bajo',
            isSelected: showLowStock,
            selectedColor: AppColors.warning,
            onTap: onToggleLowStock,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chip individual
// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.selectedColor,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final activeColor = selectedColor ?? AppColors.emerald;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? activeColor : AppColors.onSurfaceMuted,
          ),
        ),
      ),
    );
  }
}
