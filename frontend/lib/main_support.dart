import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/support_mode/support_mode.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/login_provider.dart';
import 'features/auth/presentation/server_signals.dart';
import 'features/onboarding/presentation/onboarding_provider.dart';
import 'features/support_mode/data/support_token_storage.dart';
import 'features/support_mode/data/tab_browser.dart';
import 'features/support_mode/presentation/support_app.dart';
import 'features/support_mode/presentation/support_session_controller.dart';

/// Pestaña de soporte de sólo lectura (Centro de soporte, etapa 4, P37) — build propio:
///   flutter run -d web-server --web-port 8090 -t lib/main_support.dart --dart-define=API_URL=http://127.0.0.1:8000
///   flutter build web -t lib/main_support.dart
/// La abre el panel con un enlace de un uso (`/?c=…`). No tiene pantalla de
/// inicio de sesión: sin enlace o con uno vencido, dice qué hacer.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  try {
    await Hive.initFlutter();
  } catch (_) {}

  final tab = createTabBrowser();
  runApp(
    ProviderScope(
      overrides: [
        supportModeProvider.overrideWithValue(true),
        tabBrowserProvider.overrideWithValue(tab),
        secureStorageProvider.overrideWithValue(SupportTokenStorage(tab)),
        // La sesión es la de soporte: la app nunca muestra su inicio de sesión ni el asistente
        sessionProvider.overrideWith((ref) => true),
        onboardingCompleteProvider.overrideWith((ref) => true),
        mustChangePasswordProvider.overrideWith((ref) => false),
        serverSignalHandlerProvider.overrideWith(
          (ref) => (code) {
            ref.read(supportSessionProvider.notifier).onSignal(code);
            handleServerSignal(ref, code);
          },
        ),
      ],
      child: const SupportApp(),
    ),
  );
}
