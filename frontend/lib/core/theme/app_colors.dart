import 'package:flutter/material.dart';

/// Paleta corporativa de Nexus v3.0
/// Constitución Art. I, Principio 1.2.5 — Mobile-First (tema oscuro por defecto)
abstract final class AppColors {
  // --- Fondos ---
  static const Color darkSlate = Color(0xFF0F172A);   // Fondo principal
  static const Color surface = Color(0xFF1E293B);     // Tarjetas y paneles
  static const Color surfaceVariant = Color(0xFF334155); // Input / chips

  // --- Primarios ---
  static const Color emerald = Color(0xFF10B981);     // Acción primaria / éxito
  static const Color emeraldDark = Color(0xFF059669); // Pressed / hover
  static const Color skyBlue = Color(0xFF38BDF8);     // Acento / secundario

  // --- Texto ---
  static const Color onSurface = Color(0xFFF1F5F9);   // Texto principal
  static const Color onSurfaceMuted = Color(0xFF94A3B8); // Texto secundario / hints

  // --- Semáforos ---
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF38BDF8);

  // --- Bordes ---
  static const Color border = Color(0xFF334155);
  static const Color borderFocus = Color(0xFF38BDF8);

  // Previene instanciación
  AppColors._();
}
