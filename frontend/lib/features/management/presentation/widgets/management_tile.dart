import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Renglón común de las listas de Gestión (almacenes y usuarios): mismo
/// contorno, mismo menú de acciones y mismo tratamiento de lo dado de baja.
class ManagementTile extends StatelessWidget {
  const ManagementTile({
    super.key,
    required this.itemKey,
    required this.title,
    required this.subtitle,
    this.icon,
    this.leading,
    this.badge,
    this.dimmed = false,
    this.onEdit,
    this.onDeactivate,
  });

  final Key itemKey;
  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget? leading;
  final String? badge;
  final bool dimmed;
  final VoidCallback? onEdit;
  final VoidCallback? onDeactivate;

  @override
  Widget build(BuildContext context) {
    final titleColor = dimmed ? AppColors.onSurfaceMuted : AppColors.onSurface;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: itemKey,
          contentPadding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          leading: leading ??
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon,
                    size: 20,
                    color: dimmed
                        ? AppColors.onSurfaceMuted
                        : AppColors.onSurface),
              ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.onSurfaceMuted),
            ),
          ),
          trailing: (onEdit == null && onDeactivate == null)
              ? null
              : PopupMenuButton<String>(
                  key: Key('${itemKey.toString()}-menu'),
                  color: AppColors.surfaceVariant,
                  icon: const Icon(Icons.more_vert_rounded,
                      color: AppColors.onSurfaceMuted),
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'deactivate') onDeactivate?.call();
                  },
                  itemBuilder: (_) => [
                    if (onEdit != null)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Editar',
                            style: TextStyle(color: AppColors.onSurface)),
                      ),
                    if (onDeactivate != null)
                      const PopupMenuItem(
                        value: 'deactivate',
                        child: Text('Dar de baja',
                            style: TextStyle(color: AppColors.error)),
                      ),
                  ],
                ),
          onTap: onEdit,
        ),
      ),
    );
  }
}
