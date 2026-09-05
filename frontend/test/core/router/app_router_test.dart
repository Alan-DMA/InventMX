import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/router/app_router.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/auth/presentation/login_screen.dart';

/// app_router_redirect_test — CA-04 y CA-05
void main() {
  Widget buildApp({required bool hasSession}) {
    return ProviderScope(
      overrides: [
        // sessionProvider es StateProvider<bool> — override directo
        sessionProvider.overrideWith((ref) => hasSession),
      ],
      child: Consumer(
        builder: (_, ref, __) {
          final router = ref.watch(appRouterProvider);
          return MaterialApp.router(
            theme: AppTheme.dark,
            routerConfig: router,
          );
        },
      ),
    );
  }

  group('AppRouter — redirect reactivo (CA-04, CA-05)', () {
    testWidgets(
      'CA-04: Sin sesión → muestra LoginScreen',
      (tester) async {
        await tester.pumpWidget(buildApp(hasSession: false));
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );

    testWidgets(
      'CA-05: Con sesión activa → muestra Dashboard, no Login',
      (tester) async {
        await tester.pumpWidget(buildApp(hasSession: true));
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.text('Dashboard — próximas tareas'), findsOneWidget);
      },
    );
  });
}
