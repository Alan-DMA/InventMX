import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_colors.dart';

/// Cuadrícula 2×2 de acciones rápidas de la ficha de producto.
///
/// Estado actual (Subtarea 3.2.2): todos los botones son placeholders visuales.
/// Tarea 4.2 conectará la lógica real de cada acción sin modificar este widget —
/// solo se reemplazarán los callbacks recibidos por parámetro.
///
/// Acciones:
///   Ajustar stock  (4.2.1) · Trasladar     (4.2.2)
///   Ver Kardex     (4.2)   · Etiqueta       (4.2.3)
class ActionGrid extends StatelessWidget {
  const ActionGrid({
    super.key,
    required this.onAdjustStock,
    required this.onTransfer,
    required this.onKardex,
    required this.onLabel,
  });

  final VoidCallback onAdjustStock;
  final VoidCallback onTransfer;
  final VoidCallback onKardex;
  final VoidCallback onLabel;

  static const _actions = [
    _ActionItem(
      key: 'adjust',
      icon: Icons.tune_rounded,
      label: 'Ajustar stock',
      subtitle: 'Mermas o conteos',
    ),
    _ActionItem(
      key: 'transfer',
      icon: Icons.swap_horiz_rounded,
      label: 'Trasladar',
      subtitle: 'Entre almacenes',
    ),
    _ActionItem(
      key: 'kardex',
      icon: Icons.history_rounded,
      label: 'Ver Kardex',
      subtitle: 'Historial de stock',
    ),
    _ActionItem(
      key: 'label',
      icon: Icons.label_outline_rounded,
      label: 'Etiqueta',
      subtitle: 'Código barras',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final callbacks = [onAdjustStock, onTransfer, onKardex, onLabel];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.4,
      ),
      itemCount: _actions.length,
      itemBuilder: (context, index) => _ActionButton(
        item: _actions[index],
        onTap: callbacks[index],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Botón individual de acción
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.item,
    required this.onTap,
  });

  final _ActionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.icon,
                  size: 18,
                  color: AppColors.onSurfaceMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.onSurfaceMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modelo de ítem
// ---------------------------------------------------------------------------

class _ActionItem {
  const _ActionItem({
    required this.key,
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  final String key;
  final IconData icon;
  final String label;
  final String subtitle;
}
