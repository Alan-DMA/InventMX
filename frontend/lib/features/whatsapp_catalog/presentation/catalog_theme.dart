import 'package:flutter/material.dart';

/// Tema claro propio de la vitrina pública — Tarea 13.2 (decisión D1).
///
/// La app del tendero es oscura (`AppTheme.dark`) porque es una herramienta de
/// trabajo; la vitrina la abre un cliente en la calle, a plena luz, en un
/// teléfono barato. Blanco puro (no crema: legibilidad bajo el sol), tinta
/// casi negra, gris solo para lo secundario y **un** acento: el esmeralda de
/// la marca, oscurecido a `#047857` (≈5.5:1 con texto blanco encima; el
/// `#059669` original daba 3.8:1 y la vitrina se lee bajo el sol).
///
/// Tipografía del sistema a propósito: `google_fonts` descarga Inter en el
/// primer render y la vitrina promete ser ligera con datos móviles.
abstract final class CatalogColors {
  static const Color ground = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF111827);
  static const Color inkMuted = Color(0xFF6B7280);
  static const Color line = Color(0xFFE5E7EB);
  static const Color tile = Color(0xFFF3F4F6);
  static const Color accent = Color(0xFF047857);
  static const Color accentPressed = Color(0xFF065F46);
  static const Color accentSoft = Color(0xFFD1FAE5);
  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color danger = Color(0xFFB91C1C);
  static const Color dangerSoft = Color(0xFFFEE2E2);

  /// Tinte del placeholder de foto por categoría (D4): el hueco 1:1 tiene
  /// color e ícono propios en vez de un gris uniforme que lee como "roto".
  static Color tileFor(String? category) {
    final key = (category ?? '').toLowerCase();
    if (key.contains('bebida')) return const Color(0xFFDBEAFE);
    if (key.contains('botana')) return const Color(0xFFFEF3C7);
    if (key.contains('panader')) return const Color(0xFFFFEDD5);
    if (key.contains('lácteo') || key.contains('lacteo')) {
      return const Color(0xFFF1F5F9);
    }
    if (key.contains('limpieza')) return const Color(0xFFCCFBF1);
    if (key.contains('combo')) return const Color(0xFFFCE7F3);
    return tile;
  }

  static IconData iconFor(String? category) {
    final key = (category ?? '').toLowerCase();
    if (key.contains('bebida')) return Icons.local_drink_outlined;
    if (key.contains('botana')) return Icons.cookie_outlined;
    if (key.contains('panader')) return Icons.bakery_dining_outlined;
    if (key.contains('lácteo') || key.contains('lacteo')) {
      return Icons.egg_outlined;
    }
    if (key.contains('limpieza')) return Icons.cleaning_services_outlined;
    if (key.contains('combo')) return Icons.inventory_2_outlined;
    return Icons.shopping_basket_outlined;
  }
}

abstract final class CatalogTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: CatalogColors.ground,
      colorScheme: const ColorScheme.light(
        primary: CatalogColors.accent,
        onPrimary: CatalogColors.onAccent,
        secondary: CatalogColors.accent,
        onSecondary: CatalogColors.onAccent,
        surface: CatalogColors.ground,
        onSurface: CatalogColors.ink,
        error: CatalogColors.danger,
        onError: CatalogColors.onAccent,
        outline: CatalogColors.line,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: CatalogColors.ink,
        displayColor: CatalogColors.ink,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: CatalogColors.accent,
        selectionColor: CatalogColors.accentSoft,
        selectionHandleColor: CatalogColors.accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CatalogColors.tile,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(color: CatalogColors.inkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: CatalogColors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: CatalogColors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: CatalogColors.danger, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CatalogColors.accent,
          foregroundColor: CatalogColors.onAccent,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: base.textTheme.labelLarge
              ?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CatalogColors.ink,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: CatalogColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: CatalogColors.accent),
      ),
      dividerTheme: const DividerThemeData(
        color: CatalogColors.line,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: CatalogColors.ground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: CatalogColors.ink,
        contentTextStyle: TextStyle(color: CatalogColors.ground),
        behavior: SnackBarBehavior.floating,
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  /// Cifras alineadas: los precios de una columna deben leerse como tabla.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];
}

/// `$1,234.50` — formato de la vitrina, con separador de miles.
String mxn(double value) {
  final fixed = value.toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final intPart = fixed.substring(0, dot);
  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    final fromEnd = intPart.length - i;
    buffer.write(intPart[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buffer.write(',');
  }
  return '\$$buffer${fixed.substring(dot)}';
}
