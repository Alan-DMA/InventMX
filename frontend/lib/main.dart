import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/storage/secure_storage.dart';
import 'features/auth/presentation/login_provider.dart';
import 'features/onboarding/data/onboarding_repository.dart';
import 'features/onboarding/presentation/onboarding_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Hive para caché local de solo lectura
  // (catálogo de productos, preferencias de UI — nunca tokens).
  // Constitución Art. II (Sección 2.4: Caché Local Solo Lectura)
  await Hive.initFlutter();

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
  // forma el primer redirect ya tiene el estado correcto.
  final storage = SecureStorage();
  final hasSession = await storage.hasSession();

  final onboardingRepo = OnboardingRepositoryHive();
  final onboardingData = await onboardingRepo.load();
  final onboardingDone = onboardingData.isCompleted;
  // ───────────────────────────────────────────────────────────────────────

  // Orientación preferida: portrait en móvil, libre en tablet/web.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Estilo de la barra de sistema coherente con el tema oscuro.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0F172A), // AppColors.darkSlate
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    ProviderScope(
      // Inyectamos los valores reales hidratados desde disco.
      // Esto garantiza que GoRouter evalúe el redirect correcto
      // en su primera ejecución, sin parpadeo ni pantalla incorrecta.
      overrides: [
        sessionProvider.overrideWith((ref) => hasSession),
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
