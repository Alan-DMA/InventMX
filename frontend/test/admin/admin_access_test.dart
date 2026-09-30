import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/admin/access/domain/access_models.dart';
import 'package:nexus_app/admin/core/admin_http.dart';
import 'package:nexus_app/admin/core/browser/session_store.dart';
import 'package:nexus_app/admin/router/admin_routes.dart';
import 'package:nexus_app/admin/session/admin_session.dart';

import 'admin_harness.dart';

/// Panel de plataforma, etapa 3a — acceso y sesión. Criterios: CA-S3.1 sin
/// contraseña + código no se entra; la vinculación muestra QR y códigos una
/// sola vez · CA-S3.2 la sesión vencida regresa a donde estaba.
void main() {
  testWidgets('sin sesión todo lleva al acceso, con la franja desde el primer paso', (tester) async {
    final app = await pumpAdmin(tester);
    expect(app.location, startsWith(AdminRoutes.access));
    expect(find.byKey(const Key('platformStrip')), findsOneWidget);
    expect(find.text('PANEL DE PLATAFORMA'), findsOneWidget);
    expect(find.text('Entrar al panel'), findsOneWidget);
    expect(find.byKey(const Key('platformStripSignOut')), findsNothing);
  });

  testWidgets('contraseña incorrecta: mensaje junto al formulario, sin avanzar', (tester) async {
    await pumpAdmin(tester);
    await tester.enterText(find.byKey(const Key('accessEmail')), 'eduardo@nexus.mx');
    await tester.enterText(find.byKey(const Key('accessPassword')), 'otra');
    await tester.tap(find.byKey(const Key('accessSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    expect(find.byKey(const Key('accessPasswordStep')), findsOneWidget);
  });

  testWidgets('contraseña → código: el código se envía solo; uno malo se borra y lo explica', (tester) async {
    final app = await pumpAdmin(tester);
    await tester.enterText(find.byKey(const Key('accessEmail')), 'eduardo@nexus.mx');
    await tester.enterText(find.byKey(const Key('accessPassword')), 'correcta');
    await tester.tap(find.byKey(const Key('accessSubmit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('accessCodeStep')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('accessCodeField')), '999999');
    await tester.pumpAndSettle();
    expect(find.textContaining('Código incorrecto o ya usado'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('accessCodeField'))).controller!.text, isEmpty);

    await tester.enterText(find.byKey(const Key('accessCodeField')), '123456');
    await tester.pumpAndSettle();
    expect(app.location, AdminRoutes.today);
    expect(find.text('Eduardo'), findsOneWidget); // franja: primer nombre
    expect(find.text('Sesión: 2 h'), findsOneWidget);
    expect(find.byKey(const Key('platformStripSignOut')), findsOneWidget);
  });

  testWidgets('pasaron los 5 minutos del reto: vuelve a la contraseña con la verdad', (tester) async {
    final app = await pumpAdmin(tester);
    await tester.enterText(find.byKey(const Key('accessEmail')), 'eduardo@nexus.mx');
    await tester.enterText(find.byKey(const Key('accessPassword')), 'correcta');
    await tester.tap(find.byKey(const Key('accessSubmit')));
    await tester.pumpAndSettle();

    app.clock.advance(const Duration(minutes: 6));
    await tester.enterText(find.byKey(const Key('accessCodeField')), '123456');
    await tester.pumpAndSettle();
    expect(app.access.verifyCalls, 0);
    expect(find.byKey(const Key('accessPasswordStep')), findsOneWidget);
    expect(find.textContaining('Pasaron más de 5 minutos'), findsOneWidget);
    // El correo se conserva
    expect(tester.widget<TextField>(find.byKey(const Key('accessEmail'))).controller!.text, 'eduardo@nexus.mx');
  });

  testWidgets('bloqueo por intentos: dice hasta qué hora, en la hora del equipo', (tester) async {
    final clock = TestClock(DateTime.utc(2026, 9, 30, 14, 25).toLocal());
    final access = FakeAccess(clock, lockedMessage: 'Cuenta bloqueada por intentos fallidos hasta las 14:35 UTC.');
    await pumpAdmin(tester, clock: clock, access: access);
    await tester.enterText(find.byKey(const Key('accessEmail')), 'eduardo@nexus.mx');
    await tester.enterText(find.byKey(const Key('accessPassword')), 'correcta');
    await tester.tap(find.byKey(const Key('accessSubmit')));
    await tester.pumpAndSettle();

    final local = DateTime.utc(2026, 9, 30, 14, 35).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    expect(find.textContaining('a las ${two(local.hour)}:${two(local.minute)} (hora de tu equipo)'), findsOneWidget);
    expect(find.byIcon(Icons.lock_clock_outlined), findsOneWidget);
  });

  testWidgets('primer acceso: QR + clave, luego los 10 códigos una sola vez y "Ya los guardé" sin marcar',
      (tester) async {
    final clock = TestClock(DateTime(2026, 9, 30, 20));
    final app = await pumpAdmin(tester, clock: clock, access: FakeAccess(clock, enrollment: true));
    await tester.enterText(find.byKey(const Key('accessEmail')), 'eduardo@nexus.mx');
    await tester.enterText(find.byKey(const Key('accessPassword')), 'correcta');
    await tester.tap(find.byKey(const Key('accessSubmit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('accessEnrollStep')), findsOneWidget);
    expect(find.byKey(const Key('accessEnrollQr')), findsOneWidget);
    expect(find.text('JBSW Y3DP EHPK 3PXP'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('accessCodeField')), '123456');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('accessCodesStep')), findsOneWidget);
    expect(find.text('AAAA0-BBBB0'), findsOneWidget);
    expect(find.text('AAAA9-BBBB9'), findsOneWidget);
    // Aún no hay sesión: primero se guardan los códigos
    expect(app.container.read(adminSessionProvider).signedIn, isFalse);

    final checkbox = tester.widget<CheckboxListTile>(find.byKey(const Key('accessSavedCodes')));
    expect(checkbox.value, isFalse);
    expect(tester.widget<FilledButton>(find.byKey(const Key('accessSubmit'))).onPressed, isNull);

    await tester.tap(find.byKey(const Key('accessSavedCodes')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('accessSubmit')));
    await tester.pumpAndSettle();
    expect(app.location, AdminRoutes.today);
  });

  testWidgets('código de recuperación: entra y avisa cuántos quedan; el aviso se cierra', (tester) async {
    final app = await pumpAdmin(tester);
    await tester.enterText(find.byKey(const Key('accessEmail')), 'eduardo@nexus.mx');
    await tester.enterText(find.byKey(const Key('accessPassword')), 'correcta');
    await tester.tap(find.byKey(const Key('accessSubmit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accessUseRecovery')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('accessRecoveryField')), 'ZZZZZ-99999');
    await tester.tap(find.byKey(const Key('accessSubmit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cada código sirve una sola vez'), findsWidgets);

    await tester.enterText(find.byKey(const Key('accessRecoveryField')), 'ABCDE-12345');
    await tester.tap(find.byKey(const Key('accessSubmit')));
    await tester.pumpAndSettle();
    expect(app.location, AdminRoutes.today);
    expect(find.byKey(const Key('adminRecoveryNotice')), findsOneWidget);
    expect(find.textContaining('Te quedan 6'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adminRecoveryNotice')), findsNothing);
  });

  group('sesión', () {
    testWidgets('a 10 min del vencimiento la franja lo dice en ámbar', (tester) async {
      final app = await pumpAdmin(tester);
      await signIn(tester);
      app.clock.advance(const Duration(hours: 1, minutes: 51));
      await tester.pump(const Duration(seconds: 16));
      expect(find.text('Tu sesión vence en 9 min · lo que escribas se guarda'), findsOneWidget);
    });

    testWidgets('vencida: al acceso con el aviso, y al entrar regresa a donde estaba (CA-S3.2)', (tester) async {
      final app = await pumpAdmin(tester);
      await signIn(tester);
      await tester.tap(find.byKey(const Key('adminNavAudit')));
      await tester.pumpAndSettle();
      expect(app.location, AdminRoutes.audit);

      app.clock.advance(const Duration(hours: 2, seconds: 1));
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(app.location, startsWith(AdminRoutes.access));
      expect(find.textContaining('Tu sesión de 2 horas terminó'), findsOneWidget);
      expect(app.store.read(AdminSessionNotifier.storageKey), isNull);

      await signIn(tester);
      expect(app.location, AdminRoutes.audit);
    });

    testWidgets('Salir: al acceso sin aviso de vencimiento', (tester) async {
      final app = await pumpAdmin(tester);
      await signIn(tester);
      await tester.tap(find.byKey(const Key('platformStripSignOut')));
      await tester.pumpAndSettle();
      expect(app.location, startsWith(AdminRoutes.access));
      expect(find.textContaining('Tu sesión de 2 horas terminó'), findsNothing);
    });

    testWidgets('F5: la sesión guardada en la pestaña se conserva', (tester) async {
      final clock = TestClock(DateTime(2026, 9, 30, 20));
      final store = MemorySessionStore();
      store.write(
        AdminSessionNotifier.storageKey,
        jsonEncode(AdminSession(
          token: 't',
          expiresAt: clock.now.add(const Duration(minutes: 70)),
          operatorName: 'Alan',
          operatorEmail: 'alan@nexus.mx',
          recoveryCodesRemaining: 10,
        ).toJson()),
      );
      final app = await pumpAdmin(tester, clock: clock, store: store);
      expect(app.location, AdminRoutes.today);
      expect(find.text('Sesión: 1 h 10 min'), findsOneWidget);
    });

    testWidgets('una sesión guardada ya vencida lleva al acceso con el aviso', (tester) async {
      final clock = TestClock(DateTime(2026, 9, 30, 20));
      final store = MemorySessionStore();
      store.write(
        AdminSessionNotifier.storageKey,
        jsonEncode(AdminSession(
          token: 't',
          expiresAt: clock.now.subtract(const Duration(minutes: 1)),
          operatorName: 'Alan',
          operatorEmail: 'alan@nexus.mx',
          recoveryCodesRemaining: 10,
        ).toJson()),
      );
      final app = await pumpAdmin(tester, clock: clock, store: store);
      expect(app.location, startsWith(AdminRoutes.access));
      expect(find.textContaining('Tu sesión de 2 horas terminó'), findsOneWidget);
    });
  });

  testWidgets('pantalla chica: la navegación pasa a una fila bajo la franja', (tester) async {
    await pumpAdmin(tester, size: const Size(420, 860));
    await signIn(tester);
    expect(find.byKey(const Key('adminNavCases')), findsOneWidget);
    await tester.tap(find.byKey(const Key('adminNavCases')));
    await tester.pumpAndSettle();
    expect(find.text('Sin casos esperando'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('reglas', () {
    test('volver sólo acepta rutas propias', () {
      expect(AdminRoutes.safeReturn('/casos/abc'), '/casos/abc');
      expect(AdminRoutes.safeReturn(null), AdminRoutes.today);
      expect(AdminRoutes.safeReturn('https://malo.com'), AdminRoutes.today);
      expect(AdminRoutes.safeReturn('//malo.com'), AdminRoutes.today);
      expect(AdminRoutes.safeReturn('/acceso?volver=/hoy'), AdminRoutes.today);
    });

    test('el vencimiento del reto sale del token', () {
      final exp = DateTime.utc(2026, 9, 30, 20, 5);
      expect(jwtExpiry(fakeJwt(exp)), exp);
      expect(jwtExpiry('no-es-un-token'), isNull);
    });

    test('bloqueo que cruza la medianoche UTC', () {
      final now = DateTime.utc(2026, 9, 30, 23, 55).toLocal();
      final expected = DateTime.utc(2026, 10, 1, 0, 10).toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      expect(lockedMessage('Cuenta bloqueada por intentos fallidos hasta las 00:10 UTC.', now),
          contains('${two(expected.hour)}:${two(expected.minute)}'));
      expect(lockedMessage('Otro formato', now), 'Otro formato');
    });

    test('errores del servidor en palabras del operador', () {
      expect(toAdminError(const AdminApiException('x', statusCode: 401), 'f').message, 'x');
      expect(toAdminError(Exception('boom'), 'Algo falló.').message, 'Algo falló.');
    });
  });
}
