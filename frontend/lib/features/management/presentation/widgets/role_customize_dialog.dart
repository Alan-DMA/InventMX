import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/tenant_role.dart';

/// Confirmación de la **primera** personalización de un rol del sistema.
///
/// Los cuatro roles vienen de fábrica y los comparten todos los comercios;
/// al cambiar un permiso, la tienda se queda con su propia versión y los
/// empleados que tenían el rol estándar pasan a ella. Eso es justo lo que el
/// dueño quiere ("mis cajeros ahora pueden X"), pero conviene decírselo antes
/// y con el número delante — decisión de Eduardo, Sep 23.
///
/// Devuelve `true` si el dueño confirma. A partir de ahí el rol ya es suyo y
/// las siguientes ediciones no vuelven a preguntar.
Future<bool> confirmRoleCustomization(
  BuildContext context, {
  required TenantRole role,
  required int affectedMembers,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Ajustar el rol ${role.label} a tu tienda'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"${role.label}" viene configurado de fábrica. Al cambiarlo, tu '
            'negocio se queda con su propia versión y el estándar deja de '
            'aplicarle.',
            style: const TextStyle(height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.groups_outlined,
                  size: 18, color: AppColors.skyBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _affectedLine(role, affectedMembers),
                  key: const Key('roleCustomizeAffected'),
                  style: const TextStyle(
                      fontSize: 13, height: 1.4, color: AppColors.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Puedes volver al estándar cuando quieras con "Restablecer".',
            style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('roleCustomizeConfirm'),
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.emerald,
            foregroundColor: AppColors.darkSlate,
          ),
          child: const Text('Ajustar a mi tienda'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// "Se aplica a los 3 empleados con este rol y a los que des de alta después."
String _affectedLine(TenantRole role, int affected) {
  if (affected == 0) {
    return 'Ahora mismo nadie tiene este rol: se aplicará a quien se lo '
        'asignes de aquí en adelante.';
  }
  if (affected == 1) {
    return 'Se aplica a la persona que ya tiene este rol y a las que des de '
        'alta después.';
  }
  return 'Se aplica a las $affected personas que ya tienen este rol y a las '
      'que des de alta después.';
}

/// Confirmación de "Restablecer": vuelve al estándar y se pierde el ajuste.
Future<bool> confirmRoleReset(
  BuildContext context, {
  required TenantRole role,
  required int affectedMembers,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Restablecer ${role.label}'),
      content: Text(
        affectedMembers == 0
            ? 'El rol vuelve a su configuración de fábrica y se pierden los '
                'cambios que hiciste.'
            : 'El rol vuelve a su configuración de fábrica. '
                '${affectedMembers == 1 ? 'La persona que lo tiene recupera' : 'Las $affectedMembers personas que lo tienen recuperan'} '
                'los permisos estándar.',
        style: const TextStyle(height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('roleResetConfirm'),
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: AppColors.darkSlate,
          ),
          child: const Text('Restablecer'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
