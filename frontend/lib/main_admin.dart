import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'admin/admin_app.dart';

/// Panel de plataforma — build propio:
///   flutter run -d chrome -t lib/main_admin.dart --dart-define=API_URL=http://127.0.0.1:8000
///   flutter build web -t lib/main_admin.dart
/// Rutas con `#` (por omisión): el panel se puede servir como archivos
/// estáticos sin reescrituras en el servidor.
void main() {
  // Inter viaja en `assets/google_fonts/`: el panel no pide nada a terceros y
  // el primer pintado ya sale con su fuente.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/google_fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['google_fonts'], license);
  });
  runApp(const ProviderScope(child: AdminApp()));
}
