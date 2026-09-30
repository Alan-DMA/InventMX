import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/router/app_router.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/auth/presentation/enter_code_screen.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/auth/presentation/login_screen.dart';
import 'package:nexus_app/features/auth/presentation/recover_access_screen.dart';
import 'package:nexus_app/features/auth/presentation/set_new_password_screen.dart';
import 'package:nexus_app/features/auth/presentation/widgets/auth_layout.dart';
import 'package:nexus_app/features/support/presentation/case_form_screen.dart';
import 'package:nexus_app/features/support/presentation/topic_help_screen.dart';

import 'support_app_harness.dart';

/// Recuperar acceso (Centro de soporte, etapa 2b · P16). Criterios:
/// CA-S2.1 pedir el código no revela si el correo existe · CA-S2.2 con el
/// código se entra y no se usa la app —ni al reabrirla— hasta poner contraseña
/// nueva · CA-S2.3 el código de soporte entra por "Ya tengo un código".
void main() {
  group('AccessCodeFormatter', () {
    TextEditingValue format(String text) =>
        AccessCodeFormatter().formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text));

    test('mayúsculas, guion tras cuatro y tope de ocho', () {
      expect(format('k7pmq3xr').text, 'K7PM-Q3XR');
      expect(format('k7p').text, 'K7P');
      expect(format('k7pm-q3xr-zz').text, 'K7PM-Q3XR');
      expect(format(' k7 pm*q3').text, 'K7PM-Q3');
    });
  });

  testWidgets('desde el login: pedir código lleva a "Revisa tu correo" con el mismo mensaje para cualquier correo',
      (tester) async {
    await pumpSupportApp(tester, hasSession: false);
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'nadie@correo.mx');
    await tester.tap(find.byKey(const Key('loginForgotPassword')));
    await tester.pumpAndSettle();
    expect(find.byType(RecoverAccessScreen), findsOneWidget);
    // El correo del login viene prellenado
    expect(find.widgetWithText(TextFormField, 'nadie@correo.mx'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recoverSendButton')));
    await tester.pumpAndSettle();
    expect(find.byType(EnterCodeScreen), findsOneWidget);
    expect(find.text('Revisa tu correo'), findsOneWidget);
    expect(find.textContaining('Si nadie@correo.mx tiene una cuenta en Nexus'), findsOneWidget);
    // Recién enviado: el reenvío espera y lo dice
    expect(find.text('Reenviar en 60 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Reenviar código'), findsOneWidget);
  });

  testWidgets('código equivocado: el error queda junto al campo', (tester) async {
    final app = await pumpSupportApp(tester, hasSession: false);
    await goTo(tester, app, AppRoutes.recoverCodePath(demoOwnerEmail, sent: false));
    expect(find.text('Escribe tu código'), findsOneWidget);

    final enter = find.byKey(const Key('codeEnterButton'));
    await tester.enterText(find.byKey(const Key('codeField')), 'AAAA');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.descendant(of: enter, matching: find.byType(ElevatedButton))).onPressed,
        isNull, reason: 'incompleto no se envía');

    await tester.enterText(find.byKey(const Key('codeField')), 'AAAAAAAA');
    await tester.pump();
    expect(find.text('AAAA-AAAA'), findsOneWidget);
    await tester.tap(enter);
    await tester.pumpAndSettle();
    expect(find.text(kWrongCodeMessage), findsOneWidget);
    expect(find.byType(EnterCodeScreen), findsOneWidget);
  });

  testWidgets('con el código entra, la app exige contraseña nueva y al guardarla libera el tablero',
      (tester) async {
    final app = await pumpSupportApp(tester, hasSession: false);
    await goTo(tester, app, AppRoutes.recoverCodePath(demoOwnerEmail, sent: false));

    await tester.enterText(find.byKey(const Key('codeField')), 'nxs22026');
    await tester.pump();
    await tester.tap(find.byKey(const Key('codeEnterButton')));
    await tester.pumpAndSettle();

    expect(find.byType(SetNewPasswordScreen), findsOneWidget);
    expect(app.container!.read(mustChangePasswordProvider), isTrue);
    expect(await app.storage.readMustChangePassword(), isTrue);

    // Ninguna otra ruta: el router lo regresa
    await goTo(tester, app, AppRoutes.sales);
    expect(find.byType(SetNewPasswordScreen), findsOneWidget);

    await tester.enterText(find.byKey(const Key('newPasswordField')), 'corta');
    await tester.enterText(find.byKey(const Key('confirmPasswordField')), 'corta');
    await tester.tap(find.byKey(const Key('newPasswordSaveButton')));
    await tester.pumpAndSettle();
    expect(find.text('Usa al menos 8 caracteres.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('newPasswordField')), 'NuevaClave2026');
    await tester.enterText(find.byKey(const Key('confirmPasswordField')), 'OtraClave2026');
    await tester.tap(find.byKey(const Key('newPasswordSaveButton')));
    await tester.pumpAndSettle();
    expect(find.text('Las dos contraseñas no coinciden.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('confirmPasswordField')), 'NuevaClave2026');
    await tester.tap(find.byKey(const Key('newPasswordSaveButton')));
    await tester.pumpAndSettle();
    expect(find.byType(SetNewPasswordScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(app.container!.read(mustChangePasswordProvider), isFalse);
    expect(await app.storage.readMustChangePassword(), isFalse);
  });

  testWidgets('al reabrir la app con el cambio pendiente, lo primero es "Pon una contraseña nueva"',
      (tester) async {
    await pumpSupportApp(tester, mustChangePassword: true);
    expect(find.byType(SetNewPasswordScreen), findsOneWidget);
    // Nunca un callejón: siempre se puede cerrar sesión
    await tester.tap(find.byKey(const Key('newPasswordLogout')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('sin sesión, "Escribir a soporte" lleva a la ayuda y al formulario de "No puedo entrar"',
      (tester) async {
    final app = await pumpSupportApp(tester, hasSession: false);
    await goTo(tester, app, AppRoutes.recover);
    await tester.tap(find.byKey(const Key('recoverContactSupport')));
    await tester.pumpAndSettle();
    expect(find.byType(TopicHelpScreen), findsOneWidget);
    expect(find.text('No puedo entrar a mi cuenta'), findsOneWidget);
    // La acción de la ayuda que sirve sin sesión
    expect(find.text('Pedir un código'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const Key('topicNeedHelp')), 200);
    await tester.tap(find.byKey(const Key('topicNeedHelp')));
    await tester.pumpAndSettle();
    expect(find.byType(CaseFormScreen), findsOneWidget);

    final list = find.descendant(of: find.byType(CaseFormScreen), matching: find.byType(Scrollable)).first;
    Future<void> scrollTo(Finder f, [double delta = 200]) =>
        tester.scrollUntilVisible(f, delta, scrollable: list);

    // Falta todo: nada sale
    await scrollTo(find.byKey(const Key('caseSendButton')));
    await tester.tap(find.byKey(const Key('caseSendButton')));
    await tester.pumpAndSettle();
    expect(app.support.publicCases, isEmpty);
    await scrollTo(find.byKey(const Key('publicAccountEmail')), -200);
    await tester.enterText(find.byKey(const Key('publicAccountEmail')), 'chuy@tienda.mx');
    await tester.enterText(find.byKey(const Key('publicStoreName')), 'Abarrotes Doña Chuy');
    await scrollTo(find.byKey(const Key('caseChoice_problem_Perdí acceso a mi correo')));
    await tester.tap(find.byKey(const Key('caseChoice_problem_Perdí acceso a mi correo')));
    await scrollTo(find.byKey(const Key('caseDescription')));
    await tester.enterText(find.byKey(const Key('caseDescription')), 'Cambié de celular y ya no tengo ese correo.');
    await scrollTo(find.byKey(const Key('caseSendButton')));
    await tester.tap(find.byKey(const Key('caseSendButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('publicCaseAccepted')), findsOneWidget);
    expect(app.support.publicCases.single['contact_email'], 'chuy@tienda.mx'); // vacío → el de la cuenta
    expect(app.support.publicCases.single['problem'], 'Perdí acceso a mi correo');
  });
}
