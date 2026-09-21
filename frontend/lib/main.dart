import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/storage/secure_storage.dart';
import 'features/auth/presentation/login_provider.dart';
import 'features/onboarding/data/onboarding_repository.dart';
import 'features/onboarding/presentation/onboarding_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: `/tienda/{slug}/pedido/{folio}` en vez de `/#/tienda/...` — el enlace
  // del chat de WhatsApp sólo se vuelve clicable sin `#` (QA 20 sep 2026).
  // El servidor que entregue la vitrina debe devolver index.html para
  // cualquier ruta (el backend lo hace en desarrollo; nginx `try_files` en prod).
  usePathUrlStrategy();
  debugPrint('[Nexus] main() started');

  bool hasSession = false;
  bool onboardingDone = false;
  String? sessionEmail;

  // ── Hidratación de estado persistido ANTES del runApp ──────────────────
  //
  // Problema: sessionProvider y onboardingCompleteProvider son
  // StateProvider<bool> que arrancan en `false`. GoRouter los evalúa
  // síncronamente en su primer redirect — si no están hidratados con los
  // datos reales de SecureStorage/Hive, el router manda al login/wizard
  // aunque el usuario ya hubiera autenticado y completado el onboarding.
  //
  // Solución: leer ambas fuentes de persistencia aquí, antes del runApp,
  // y pasar los valores reales como `overrides` al ProviderScope. De esta
  // forma el primer redirect ya tiene el estado correcto. Envuelto en
  // try/catch: un storage corrupto o Hive sin inicializar no debe tumbar
  // el arranque de la app, sólo dejarla en el estado por defecto (login).
  try {
    await Hive.initFlutter();

    final storage = SecureStorage();
    hasSession = await storage.hasSession();
    sessionEmail = await storage.readUserEmail();

    final onboardingRepo = OnboardingRepositoryHive();
    final onboardingData = await onboardingRepo.load();
    onboardingDone = onboardingData.isCompleted;
  } catch (e, st) {
    debugPrint('[Nexus] Error hydrating storage: $e\n$st');
  }

  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0F172A),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  debugPrint('[Nexus] runApp() launching with hasSession=$hasSession, onboardingDone=$onboardingDone');

  runApp(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => hasSession),
        currentUserNameProvider.overrideWith((ref) => sessionEmail),
        onboardingCompleteProvider.overrideWith((ref) => onboardingDone),
      ],
      child: const NexusApp(),
    ),
  );
}


/// Widget raíz de la aplicación Nexus.
///
/// ConsumerWidget para acceder a appRouterProvider sin
/// necesitar un BuildContext adicional.
class NexusApp extends ConsumerWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Nexus',
      debugShowCheckedModeBanner: false,

      // Tema oscuro corporativo como único tema (Mobile-First Android).
      // Constitución Art. I, Principio 1.2.5
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,

      // GoRouter como sistema de navegación declarativo.
      routerConfig: router,
    );
  }
}
