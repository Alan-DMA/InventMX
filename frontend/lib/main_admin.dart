import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin/admin_app.dart';

/// Panel de plataforma — build propio:
///   flutter run -d chrome -t lib/main_admin.dart --dart-define=API_URL=http://127.0.0.1:8000
///   flutter build web -t lib/main_admin.dart
/// Rutas con `#` (por omisión): el panel se puede servir como archivos
/// estáticos sin reescrituras en el servidor.
void main() {
  runApp(const ProviderScope(child: AdminApp()));
}
