import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus_app/core/theme/app_colors.dart';
import 'package:nexus_app/core/theme/app_theme.dart';

/// app_theme_colors_test — CA planificado en bitácora Tarea 1.2
///
/// Estrategia de test:
/// - AppColors: tests unitarios puros (no necesitan binding).
/// - AppTheme.dark: testWidgets con binding inicializado +
///   GoogleFonts.config.allowRuntimeFetching = false para evitar
///   intentos de carga de assets en entorno headless.
void main() {
  // Desactiva la descarga de fuentes en red durante todos los tests.
  // google_fonts usa el sistema de assets de Flutter, que requiere binding.
  // Con esta flag usa el fallback del sistema sin lanzar errores.
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // --------------------------------------------------------------------------
  // AppColors — tests unitarios puros (no requieren binding)
  // --------------------------------------------------------------------------

  group('AppColors — tokens corporativos', () {
    test('darkSlate es #0F172A', () {
      expect(AppColors.darkSlate, const Color(0xFF0F172A));
    });

    test('emerald es #10B981', () {
      expect(AppColors.emerald, const Color(0xFF10B981));
    });

    test('skyBlue es #38BDF8', () {
      expect(AppColors.skyBlue, const Color(0xFF38BDF8));
    });

    test('surface es #1E293B', () {
      expect(AppColors.surface, const Color(0xFF1E293B));
    });

    test('onSurface es #F1F5F9', () {
      expect(AppColors.onSurface, const Color(0xFFF1F5F9));
    });

    test('error es #EF4444', () {
      expect(AppColors.error, const Color(0xFFEF4444));
    });
  });

  // --------------------------------------------------------------------------
  // AppTheme.dark — testWidgets porque construye ThemeData con GoogleFonts
  // El binding se inicializa automáticamente en testWidgets.
  // --------------------------------------------------------------------------

  group('AppTheme.dark — ThemeData', () {
    testWidgets('scaffoldBackgroundColor es darkSlate', (tester) async {
      final theme = AppTheme.dark;
      expect(theme.scaffoldBackgroundColor, AppColors.darkSlate);
    });

    testWidgets('colorScheme.primary es emerald', (tester) async {
      final theme = AppTheme.dark;
      expect(theme.colorScheme.primary, AppColors.emerald);
    });

    testWidgets('colorScheme.secondary es skyBlue', (tester) async {
      final theme = AppTheme.dark;
      expect(theme.colorScheme.secondary, AppColors.skyBlue);
    });

    testWidgets('colorScheme.surface es surface', (tester) async {
      final theme = AppTheme.dark;
      expect(theme.colorScheme.surface, AppColors.surface);
    });

    testWidgets('colorScheme.error es error', (tester) async {
      final theme = AppTheme.dark;
      expect(theme.colorScheme.error, AppColors.error);
    });

    testWidgets('useMaterial3 está habilitado', (tester) async {
      final theme = AppTheme.dark;
      expect(theme.useMaterial3, isTrue);
    });

    testWidgets('elevatedButton tiene altura mínima de 52', (tester) async {
      final theme = AppTheme.dark;
      final minSize = theme.elevatedButtonTheme.style?.minimumSize?.resolve({});
      expect(minSize?.height, 52);
    });

    testWidgets('inputDecoration tiene borderRadius de 12', (tester) async {
      final theme = AppTheme.dark;
      final border = theme.inputDecorationTheme.border as OutlineInputBorder?;
      expect(border?.borderRadius, BorderRadius.circular(12));
    });
  });
}
