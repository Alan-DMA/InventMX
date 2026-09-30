import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'admin_colors.dart';

/// Estado de una tienda escrito (nunca sólo color), el mismo en la ficha, la
/// búsqueda y los casos. Rojo = suspendida por soporte; ámbar = bloqueada o
/// en sólo lectura.
(String, Color) storeStatus(String status, String? lockReason) {
  if (lockReason == 'ABUSE' && status != 'ACTIVE') return ('Suspendida por soporte', AppColors.error);
  return switch (status) {
    'HARD_LOCK' => ('Bloqueada por falta de pago', AdminColors.amber),
    'SOFT_LOCK' => ('Sólo lectura', AdminColors.amber),
    _ => ('Activa', AppColors.onSurface),
  };
}

String planLabel(String plan) => switch (plan) {
      'EMPRENDEDOR' => 'Plan Emprendedor',
      'COMERCIO' => 'Plan Comercio',
      'CORPORATIVO' => 'Plan Corporativo',
      _ => 'Plan $plan',
    };
