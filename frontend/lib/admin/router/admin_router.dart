import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/presentation/access_screen.dart';
import '../audit/presentation/audit_screen.dart';
import '../cases/presentation/cases_screen.dart';
import '../help_topics/presentation/help_topics_screen.dart';
import '../today/presentation/today_screen.dart';
import '../session/admin_session.dart';
import '../shell/admin_shell.dart';
import 'admin_routes.dart';

const _casesPage = ValueKey('casesPage');
const _topicsPage = ValueKey('topicsPage');

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
          child: AdminShell(location: state.matchedLocation, uri: state.uri, child: child),
        ),
        routes: [
          GoRoute(
            path: AdminRoutes.today,
            pageBuilder: (_, __) => const NoTransitionPage(key: ValueKey('todayPage'), child: TodayScreen()),
          ),
          // Cola y caso abierto comparten página: abrir un caso no reconstruye la cola
          GoRoute(
            path: AdminRoutes.cases,
            pageBuilder: (_, __) => const NoTransitionPage(key: _casesPage, child: CasesScreen()),
          ),
          GoRoute(
            path: '${AdminRoutes.cases}/:id',
            pageBuilder: (_, state) => NoTransitionPage(
              key: _casesPage,
              child: CasesScreen(selectedId: state.pathParameters['id']),
            ),
          ),
          GoRoute(
            path: AdminRoutes.audit,
            pageBuilder: (_, __) => const NoTransitionPage(key: ValueKey('auditPage'), child: AuditScreen()),
          ),
          // Lista y tema abierto comparten página
          GoRoute(
            path: AdminRoutes.helpTopics,
            pageBuilder: (_, __) => const NoTransitionPage(key: _topicsPage, child: HelpTopicsScreen()),
          ),
          GoRoute(
            path: '${AdminRoutes.helpTopics}/:key',
            pageBuilder: (_, state) => NoTransitionPage(
              key: _topicsPage,
              child: HelpTopicsScreen(selectedKey: state.pathParameters['key']),
            ),
          ),
        ],
      ),
    ],
    debugLogDiagnostics: kDebugMode,
  );
});
