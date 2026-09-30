import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Colores propios del panel de plataforma. Todo lo demás es la paleta de la
/// app del tendero (`AppColors`): el índigo es la única firma de plataforma
/// (franja, sección activa, acción principal, foco), para que nunca se
/// confunda con estar dentro de una tienda. El esmeralda sólo aparece cuando
/// el panel cita la app del tendero ("Así lo verá / Así lo leerá").
abstract final class AdminColors {
  static const Color indigo = Color(0xFF818CF8);
  static const Color indigoPressed = Color(0xFF6366F1);

  /// Fondo de la franja fija: índigo al 14 % sobre `darkSlate`.
  static const Color strip = Color(0xFF1F2747);

  /// Franja cuando la sesión está por vencer: ámbar al 14 % sobre `darkSlate`.
  static const Color stripWarning = Color(0xFF2F2A26);

  static Color get indigoSoft => indigo.withValues(alpha: 0.16);
  static Color get indigoLine => indigo.withValues(alpha: 0.4);

  static const Color amber = AppColors.warning;

  /// Botón destructivo: rojo más oscuro que `AppColors.error` para que el
  /// texto blanco pase AA (4.8:1).
  static const Color danger = Color(0xFFDC2626);

  AdminColors._();
}
