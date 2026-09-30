import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/presentation/access_screen.dart';
import '../session/admin_session.dart';
import '../shell/admin_shell.dart';
import 'admin_routes.dart';

/// Router del panel. Sin sesión todo lleva al acceso con `volver` (la ruta
/// donde estaba) y `vencio=1` si la sesión terminó sola; al entrar, regresa
/// ahí (P34). El token nunca viaja en la URL.
final adminRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(adminSessionProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AdminRoutes.today,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(adminSessionProvider);
      final atAccess = state.matchedLocation == AdminRoutes.access;
      if (!auth.signedIn) {
        if (atAccess) return null;
        final back = Uri.encodeComponent(state.uri.toString());
        return '${AdminRoutes.access}?volver=$back${auth.expired ? '&vencio=1' : ''}';
      }
      if (atAccess) return AdminRoutes.safeReturn(state.uri.queryParameters['volver']);
      if (state.matchedLocation == '/') return AdminRoutes.today;
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => AdminRoutes.today),
      GoRoute(
        path: AdminRoutes.access,
        pageBuilder: (context, state) => NoTransitionPage(
          child: AccessScreen(sessionEnded: state.uri.queryParameters['vencio'] == '1'),
        ),
      ),
      ShellRoute(
        pageBuilder: (context, state, child) => NoTransitionPage(
          child: AdminShell(location: state.matchedLocation, child: child),
        ),
        routes: [
          GoRoute(
            path: AdminRoutes.today,
            pageBuilder: (_, __) => const NoTransitionPage(
              child: AdminPendingSection(
                title: 'Hoy',
                arrivesIn: 'etapa 3c',
                what: 'Lo que requiere atención, lo que pasó por día, las métricas y el buscador de tiendas.',
              ),
            ),
          ),
          GoRoute(
            path: AdminRoutes.cases,
            pageBuilder: (_, __) => const NoTransitionPage(
              child: AdminPendingSection(
                title: 'Casos',
                arrivesIn: 'etapa 3b',
                what: 'La cola de casos de soporte con su conversación y las respuestas al tendero.',
              ),
            ),
          ),
          GoRoute(
            path: AdminRoutes.audit,
            pageBuilder: (_, __) => const NoTransitionPage(
              child: AdminPendingSection(
                title: 'Bitácora',
                arrivesIn: 'etapa 3e',
                what: 'Todo lo que se hizo desde el panel, con filtros y la verificación de integridad.',
              ),
            ),
          ),
          GoRoute(
            path: AdminRoutes.helpTopics,
            pageBuilder: (_, __) => const NoTransitionPage(
              child: AdminPendingSection(
                title: 'Temas de ayuda',
                arrivesIn: 'etapa 3e',
                what: 'El texto de la ayuda que ven los tenderos en Soporte.',
              ),
            ),
          ),
        ],
      ),
    ],
    debugLogDiagnostics: kDebugMode,
  );
});
