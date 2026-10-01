import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'support_session_controller.dart';
import 'support_strip.dart';

/// Raíz de la pestaña de soporte (`main_support.dart`, etapa 4).
///
/// La franja vive fuera de la app del tendero y nunca se va; debajo, la tienda
/// en una columna de teléfono (como en el Android del dueño) o, antes y
/// después, las pantallas de entrada y salida. Al terminar, la tienda se
/// retira bajo la franja y queda "El acceso terminó".
class SupportApp extends ConsumerStatefulWidget {
  const SupportApp({super.key});

  /// Ancho de la columna de la tienda: un teléfono, no una tienda estirada.
  static const phoneWidth = 480.0;

  @override
  ConsumerState<SupportApp> createState() => _SupportAppState();
}

class _SupportAppState extends ConsumerState<SupportApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(supportSessionProvider.notifier).start());
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(supportSessionProvider);
    final tenant = phase is SupportActive ? phase.status.tenantName : null;

    return MaterialApp(
      title: tenant == null ? 'Nexus · soporte' : 'Soporte · $tenant',
      debugShowCheckedModeBanner: false,
      theme: _gateTheme,
      home: Scaffold(
        backgroundColor: AppColors.darkSlate,
        body: Column(
          children: [
            const SupportStrip(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 360),
                // En secuencia, no encimadas: lo que sale se va en la primera mitad
                // y lo que entra llega en la segunda (columnas distintas no se cruzan)
                switchInCurve: const Interval(0.5, 1, curve: Curves.easeOutCubic),
                switchOutCurve: const Interval(0.5, 1, curve: Curves.easeInCubic),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                child: switch (phase) {
                  SupportActive() => const _StoreColumn(key: ValueKey('store')),
                  SupportOpening() => const _Opening(key: ValueKey('opening')),
                  SupportLinkFailed(:final message) => _Gate(
                      key: const ValueKey('failed'),
                      icon: Icons.link_off_rounded,
                      title: 'No se pudo abrir la tienda',
                      body: message,
                    ),
                  SupportClosed(:final end) => _Gate(
                      key: const ValueKey('closed'),
                      icon: Icons.lock_outline_rounded,
                      title: 'El acceso terminó',
                      body: '${end.message} No quedó nada de la tienda guardado en este navegador.',
                    ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La tienda dentro de la columna: la app real del tendero (sustituible en tests).
final supportStoreBuilderProvider = Provider<Widget Function(WidgetRef ref)>(
  (_) => (ref) => MaterialApp.router(
        key: const Key('supportStore'),
        title: 'Nexus',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        routerConfig: ref.watch(appRouterProvider),
      ),
);

/// La app real del tendero, en su propio MaterialApp, con el ancho de un teléfono.
class _StoreColumn extends ConsumerWidget {
  const _StoreColumn({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.min(constraints.maxWidth, SupportApp.phoneWidth);
      final framed = constraints.maxWidth > SupportApp.phoneWidth;
      final media = MediaQuery.of(context);
      return Center(
        child: Container(
          width: framed ? width + 2 : width,
          decoration: framed
              ? const BoxDecoration(border: Border.symmetric(vertical: BorderSide(color: AppColors.border)))
              : null,
          // La tienda cree estar en un teléfono: su MediaQuery mide la columna
          child: MediaQuery(
            data: media.copyWith(
              size: Size(width, constraints.maxHeight),
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
            ),
            child: ref.watch(supportStoreBuilderProvider)(ref),
          ),
        ),
      );
    });
  }
}

class _Opening extends StatelessWidget {
  const _Opening({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: SupportColors.indigo),
            ),
            const SizedBox(height: 20),
            Text('Abriendo la tienda…',
                style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
            const SizedBox(height: 6),
            Text('Sesión de soporte de sólo lectura',
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceMuted)),
          ],
        ),
      );
}

/// Entrada fallida o salida: una columna angosta con qué pasó y qué hacer.
class _Gate extends ConsumerWidget {
  const _Gate({super.key, required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: AppColors.onSurfaceMuted),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(title,
                    key: const Key('supportGateTitle'),
                    style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
              ),
              const SizedBox(height: 10),
              Text(body,
                  key: const Key('supportGateBody'),
                  style: GoogleFonts.inter(fontSize: 15, height: 1.5, color: AppColors.onSurface)),
              const SizedBox(height: 28),
              FilledButton(
                key: const Key('supportGateClose'),
                onPressed: () => ref.read(tabBrowserProvider).closeTab(),
                child: const Text('Cerrar esta pestaña'),
              ),
              const SizedBox(height: 10),
              Text('Si la pestaña no se cierra, ciérrala tú.',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tema de la franja y de las pantallas de entrada y salida: el del tendero con
/// el índigo de plataforma como acción (no es la tienda; es la visita).
final ThemeData _gateTheme = AppTheme.dark.copyWith(
  colorScheme: AppTheme.dark.colorScheme.copyWith(primary: SupportColors.indigo),
  progressIndicatorTheme: const ProgressIndicatorThemeData(color: SupportColors.indigo),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: SupportColors.indigo,
      foregroundColor: AppColors.darkSlate,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      textStyle: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  textSelectionTheme: TextSelectionThemeData(
    cursorColor: SupportColors.indigo,
    selectionColor: SupportColors.indigo.withValues(alpha: 0.32),
  ),
);
