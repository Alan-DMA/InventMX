import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/router/app_router.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/auth/presentation/login_screen.dart';
import 'package:nexus_app/features/onboarding/presentation/onboarding_provider.dart';
import 'package:nexus_app/features/onboarding/presentation/onboarding_wizard_screen.dart';

/// app_router_redirect_test — CA-04, CA-05, CA-08, CA-09
///
/// El router ahora tiene triple redirect:
///   sin sesión            → /login
///   sesión + sin onb.     → /onboarding
///   sesión + onb. completo → /dashboard
void main() {
  Widget buildApp({
    required bool hasSession,
    required bool onboardingDone,
  }) {
    return ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => hasSession),
        onboardingCompleteProvider.overrideWith((ref) => onboardingDone),
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

  group('AppRouter — triple redirect reactivo', () {
    testWidgets(
      'CA-04: Sin sesión → muestra LoginScreen',
      (tester) async {
        await tester.pumpWidget(
          buildApp(hasSession: false, onboardingDone: false),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );

    testWidgets(
      'CA-09: Con sesión pero onboarding incompleto → muestra OnboardingWizardScreen',
      (tester) async {
        await tester.pumpWidget(
          buildApp(hasSession: true, onboardingDone: false),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(OnboardingWizardScreen), findsOneWidget);
      },
    );

    testWidgets(
      'CA-05: Con sesión y onboarding completo → muestra Dashboard, no Login',
      (tester) async {
        await tester.pumpWidget(
          buildApp(hasSession: true, onboardingDone: true),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(OnboardingWizardScreen), findsNothing);
        expect(find.text('Dashboard — próximas tareas'), findsOneWidget);
      },
    );
  });
}
