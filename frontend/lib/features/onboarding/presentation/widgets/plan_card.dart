import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../domain/plan_option.dart';

/// Tarjeta comparativa de plan para el Paso 3.
///
/// Cambios respecto a la versión anterior:
///   - Sin botón CTA interno — la selección se confirma con el botón del footer.
///   - Planes reales de la Constitución (Emprendedor $199, Comercio $399, Corporativo $699 MXN).
///   - Sin badge "Gratis" ni precio $0 — no existe tier gratuito permanente.
///   - Borde esmeralda animado cuando isSelected = true.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.isSelected,
    required this.onTap,
  });

  final PlanOption plan;
  final bool isSelected;
  final VoidCallback onTap;

  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.emerald : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 6),
            _buildPrice(),
            _buildBadges(),
            const SizedBox(height: 14),
            ..._buildFeatures(),
          ],
        ),
      ),
    );
  }

  // ---------- Header ----------

  Widget _buildHeader() {
    final isRecommended = plan == PlanOption.comercio;

    return Row(
      children: [
        Text(
          plan.label,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.emerald : AppColors.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        if (isRecommended)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.emerald,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '★ Recomendado',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.darkSlate,
              ),
            ),
          ),
        const Spacer(),
        // Indicador de selección
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? AppColors.emerald : Colors.transparent,
            border: Border.all(
              color: isSelected ? AppColors.emerald : AppColors.border,
              width: 2,
            ),
          ),
          child: isSelected
              ? const Icon(Icons.check, size: 12, color: AppColors.darkSlate)
              : null,
        ),
      ],
    );
  }

  // ---------- Precio ----------

  Widget _buildPrice() {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '\$${plan.priceMxn}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
            ),
          ),
          const TextSpan(
            text: ' MXN/mes',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Badges ----------

  Widget _buildBadges() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          _badge(
            label: '14 días gratis',
            color: AppColors.emerald,
            bgAlpha: 0.12,
          ),
          const SizedBox(width: 8),
          _badge(
            label: _userLimitLabel(),
            color: AppColors.skyBlue,
            bgAlpha: 0.12,
          ),
        ],
      ),
    );
  }

  Widget _badge({
    required String label,
    required Color color,
    required double bgAlpha,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _userLimitLabel() {
    switch (plan) {
      case PlanOption.emprendedor:
        return 'Hasta 2 usuarios';
      case PlanOption.comercio:
        return 'Hasta 5 usuarios';
      case PlanOption.corporativo:
        return 'Hasta 15 usuarios';
      default:
        return '';
    }
  }

  // ---------- Features ----------

  List<Widget> _buildFeatures() {
    final features = _featuresForPlan();
    return features
        .map(
          (f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: AppColors.emerald,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.onSurface,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  List<String> _featuresForPlan() {
    switch (plan) {
      case PlanOption.emprendedor:
        return [
          'Inventario, ventas y compras base',
          '1 almacén principal',
          'Alertas de stock bajo',
          'Notas de venta en ticket 58mm/80mm y PDF',
          'Reportes básicos',
        ];
      case PlanOption.comercio:
        return [
          'Todo el plan Emprendedor',
          'Caja con arqueo cono Banxico',
          'Multi-almacén ilimitado',
          'Catálogo digital y pedidos por WhatsApp',
          'OCR de facturas y pagos mixtos',
        ];
      case PlanOption.corporativo:
        return [
          'Todo el plan Comercio',
          'Analítica avanzada y KPIs de rentabilidad',
          'Dashboard comparativo en tiempo real',
          'Clonación de catálogo multi-sucursal',
          'Hasta 15 usuarios con permisos granulares',
        ];
      default:
        return [];
    }
  }
}
