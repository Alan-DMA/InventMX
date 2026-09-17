import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Un grupo de renglones de una página de ajustes: etiqueta arriba y una
/// tarjeta con los renglones separados por líneas.
///
/// El agrupamiento es el que carga el significado — "esto es mío" vs. "esto
/// es del negocio" — así que la etiqueta nunca se omite.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.label, required this.rows});

  final String label;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    const Divider(
                        height: 1, thickness: 1, color: AppColors.border),
                  rows[i],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

/// Renglón de una página de ajustes. El subtítulo dice qué hay detrás, para no
/// obligar a entrar y averiguar.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.rowKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tint,
    this.trailing,
  });

  final Key rowKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? tint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? AppColors.onSurface;

    return ListTile(
      key: rowKey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Icon(icon, size: 21, color: color),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted),
      ),
      trailing: trailing ??
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceMuted),
      onTap: onTap,
    );
  }
}
