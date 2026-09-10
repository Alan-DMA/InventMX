import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Design System centralizado de Nexus v3.0
/// Tema oscuro como único tema — Constitución Art. I, Principio 1.2.5 (Mobile-First Android)
abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.darkSlate,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.emerald,
        onPrimary: AppColors.darkSlate,
        secondary: AppColors.skyBlue,
        onSecondary: AppColors.darkSlate,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        error: AppColors.error,
        onError: AppColors.onSurface,
        outline: AppColors.border,
      ),
      textTheme: _buildTextTheme(base.textTheme),
      inputDecorationTheme: _buildInputTheme(),
      elevatedButtonTheme: _buildElevatedButtonTheme(),
      outlinedButtonTheme: _buildOutlinedButtonTheme(),
      cardTheme: _buildCardTheme(),
      appBarTheme: _buildAppBarTheme(base),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      chipTheme: _buildChipTheme(),
      snackBarTheme: _buildSnackBarTheme(),
    );
  }

  // ---------- Text ----------

  static TextTheme _buildTextTheme(TextTheme base) {
    final inter = GoogleFonts.interTextTheme(base);
    return inter.copyWith(
      displayLarge: inter.displayLarge?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w700,
      ),
      displayMedium: inter.displayMedium?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: inter.headlineLarge?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 24,
      ),
      headlineMedium: inter.headlineMedium?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 20,
      ),
      titleLarge: inter.titleLarge?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
      titleMedium: inter.titleMedium?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w500,
        fontSize: 16,
      ),
      bodyLarge: inter.bodyLarge?.copyWith(
        color: AppColors.onSurface,
        fontSize: 16,
      ),
      bodyMedium: inter.bodyMedium?.copyWith(
        color: AppColors.onSurface,
        fontSize: 14,
      ),
      bodySmall: inter.bodySmall?.copyWith(
        color: AppColors.onSurfaceMuted,
        fontSize: 12,
      ),
      labelLarge: inter.labelLarge?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        letterSpacing: 0.5,
      ),
      labelSmall: inter.labelSmall?.copyWith(
        color: AppColors.onSurfaceMuted,
        fontSize: 11,
      ),
    );
  }

  // ---------- Input ----------

  static InputDecorationTheme _buildInputTheme() {
    return InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderFocus, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      hintStyle: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 14),
      labelStyle:
          const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 14),
      floatingLabelStyle:
          const TextStyle(color: AppColors.skyBlue, fontSize: 12),
      prefixIconColor: AppColors.onSurfaceMuted,
      suffixIconColor: AppColors.onSurfaceMuted,
    );
  }

  // ---------- Buttons ----------

  static ElevatedButtonThemeData _buildElevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.emerald,
        foregroundColor: AppColors.darkSlate,
        disabledBackgroundColor: AppColors.surfaceVariant,
        disabledForegroundColor: AppColors.onSurfaceMuted,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          letterSpacing: 0.3,
        ),
        elevation: 0,
      ),
    );
  }

  static OutlinedButtonThemeData _buildOutlinedButtonTheme() {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.emerald,
        side: const BorderSide(color: AppColors.emerald),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    );
  }

  // ---------- Card ----------

  static CardThemeData _buildCardTheme() {
    return CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
    );
  }

  // ---------- AppBar ----------

  static AppBarTheme _buildAppBarTheme(ThemeData base) {
    return AppBarTheme(
      backgroundColor: AppColors.darkSlate,
      foregroundColor: AppColors.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.inter(
        color: AppColors.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: const IconThemeData(color: AppColors.onSurface),
      actionsIconTheme: const IconThemeData(color: AppColors.skyBlue),
    );
  }

  // ---------- Chip ----------

  static ChipThemeData _buildChipTheme() {
    return ChipThemeData(
      backgroundColor: AppColors.surfaceVariant,
      selectedColor: AppColors.emerald.withValues(alpha: 0.2),
      disabledColor: AppColors.border,
      labelStyle: const TextStyle(color: AppColors.onSurface, fontSize: 13),
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }

  // ---------- SnackBar ----------

  static SnackBarThemeData _buildSnackBarTheme() {
    return SnackBarThemeData(
      backgroundColor: AppColors.surface,
      contentTextStyle: const TextStyle(color: AppColors.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    );
  }

  AppTheme._();
}
