import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'admin_colors.dart';

/// El tema del tendero con el índigo en el lugar del esmeralda. También se
/// tiñen las superficies que el navegador pintaría por defecto: selección de
/// texto, cursor, barras de desplazamiento y anillos de foco.
///
/// Los botones declaran su familia: sin ella, el estilo del botón no hereda
/// Inter del tema y cae en la fuente por omisión del motor.
ThemeData buildAdminTheme() {
  final base = AppTheme.dark;
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: AdminColors.indigo,
      onPrimary: AppColors.darkSlate,
    ),
    focusColor: AdminColors.indigoSoft,
    hoverColor: AppColors.surfaceVariant.withValues(alpha: 0.35),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AdminColors.indigo,
      selectionColor: AdminColors.indigo.withValues(alpha: 0.32),
      selectionHandleColor: AdminColors.indigo,
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(AppColors.surfaceVariant),
      thickness: WidgetStatePropertyAll(8),
      radius: Radius.circular(8),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: AppColors.darkSlate,
      enabledBorder: border(AppColors.border),
      focusedBorder: border(AdminColors.indigo, 1.5),
      // Material escala la etiqueta flotante a 0.75: 16 px → 12 px legibles
      floatingLabelStyle: const TextStyle(color: AdminColors.indigo, fontSize: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AdminColors.indigo,
        foregroundColor: AppColors.darkSlate,
        disabledBackgroundColor: AppColors.surfaceVariant,
        disabledForegroundColor: AppColors.onSurfaceMuted,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.onSurface,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AdminColors.indigo,
        minimumSize: const Size(0, 40),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AdminColors.indigo : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(AppColors.darkSlate),
      side: const BorderSide(color: AppColors.onSurfaceMuted, width: 1.5),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AdminColors.indigo),
    // Los chips tampoco heredan la familia del tema (los filtros de la Bitácora)
    // Apagado = contorno; encendido = índigo suave con palomita: se distinguen de un vistazo
    chipTheme: base.chipTheme.copyWith(
      labelStyle: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.onSurface),
      backgroundColor: Colors.transparent,
      // `color` manda sobre backgroundColor en Material 3: apagado = fondo de la página
      color: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AdminColors.indigoSoft : Colors.transparent,
      ),
      side: const BorderSide(color: AppColors.border),
      selectedColor: AdminColors.indigoSoft,
      checkmarkColor: AdminColors.indigo,
      showCheckmark: true,
    ),
  );
}

/// Texto de dato que se teclea o se copia (códigos, claves): mono del sistema
/// con cifras tabulares — es medida, no disfraz de "técnico".
const adminMonoStyle = TextStyle(
  fontFamily: 'monospace',
  fontFeatures: [FontFeature.tabularFigures()],
  color: AppColors.onSurface,
);
