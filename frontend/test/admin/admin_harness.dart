import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/admin/access/data/access_repository.dart';
import 'package:nexus_app/admin/access/domain/access_models.dart';
import 'package:nexus_app/admin/admin_app.dart';
import 'package:nexus_app/admin/cases/data/cases_repository.dart';
import 'package:nexus_app/admin/tenants/data/tenants_repository.dart';
import 'package:nexus_app/admin/today/data/today_repository.dart';
import 'package:nexus_app/admin/core/admin_http.dart';
import 'package:nexus_app/admin/core/browser/session_store.dart';
import 'package:nexus_app/admin/router/admin_router.dart';
import 'package:nexus_app/admin/session/admin_session.dart';

import 'fake_cases.dart';
import 'fake_today.dart';

/// Reloj que el test mueve a mano.
class TestClock {
  TestClock(this.now);
  DateTime now;
  void advance(Duration d) => now = now.add(d);
}

/// Token con la forma de un JWT y un `exp` real (sin firma válida: el panel
/// sólo lee el vencimiento).
String fakeJwt(DateTime expiresAt) {
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': expiresAt.millisecondsSinceEpoch ~/ 1000})));
  return 'eyJhbGciOiJIUzI1NiJ9.${payload.replaceAll('=', '')}.firma';
}

const unauthorized = AdminApiException('Correo, contraseña o código incorrectos.', statusCode: 401);

/// Acceso falso: correo `eduardo@nexus.mx`, contraseña `correcta`, código
/// `123456`, código de recuperación `ABCDE-12345`.
class FakeAccess implements AccessRepository {
  FakeAccess(this.clock, {this.enrollment = false, this.lockedMessage});

  final TestClock clock;
  bool enrollment;
  String? lockedMessage;
  int verifyCalls = 0;
  int recoveryRemaining = 7;

  @override
  Future<LoginChallenge> login(String email, String password) async {
    if (lockedMessage != null) throw AdminApiException(lockedMessage!, statusCode: 423);
    if (email.trim() != 'eduardo@nexus.mx' || password != 'correcta') throw unauthorized;
    final expires = clock.now.add(const Duration(minutes: 5));
    return LoginChallenge(
      token: fakeJwt(expires),
      expiresAt: expires,
      otpauthUri: enrollment ? 'otpauth://totp/Nexus%20Plataforma:eduardo@nexus.mx?secret=JBSWY3DPEHPK3PXP' : null,
      manualSecret: enrollment ? 'JBSWY3DPEHPK3PXP' : null,
    );
  }

  @override
  Future<SessionGrant> verify(String challengeToken, String code) async {
    verifyCalls++;
    if (code != '123456') throw unauthorized;
    final grant = _grant(recoveryCodes: enrollment ? [for (var i = 0; i < 10; i++) 'AAAA$i-BBBB$i'] : null);
    enrollment = false;
    return grant;
  }

  @override
  Future<SessionGrant> recover(String challengeToken, String recoveryCode) async {
    if (recoveryCode != 'ABCDE-12345') throw unauthorized;
    recoveryRemaining--;
    return _grant();
  }

  SessionGrant _grant({List<String>? recoveryCodes}) => SessionGrant(
        token: 'sesion-${clock.now.millisecondsSinceEpoch}',
        expiresIn: const Duration(hours: 2),
        operatorName: 'Eduardo Cristancho',
        operatorEmail: 'eduardo@nexus.mx',
        recoveryCodesRemaining: recoveryCodes?.length ?? recoveryRemaining,
        recoveryCodes: recoveryCodes,
      );
}

class AdminTestApp {
  AdminTestApp(this.container, this.store, this.clock, this.access);
  final ProviderContainer container;
  final MemorySessionStore store;
  final TestClock clock;
  final FakeAccess access;

  String get location => container.read(adminRouterProvider).routerDelegate.currentConfiguration.uri.toString();

  void go(String path) => container.read(adminRouterProvider).go(path);
}

/// El panel completo (router real) a 1440 × 900 sobre el acceso falso.
Future<AdminTestApp> pumpAdmin(
  WidgetTester tester, {
  TestClock? clock,
  FakeAccess? access,
  MemorySessionStore? store,
  Size size = const Size(1440, 900),
  CasesRepository? cases,
  TodayRepository? today,
  TenantsRepository? tenants,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final testClock = clock ?? TestClock(DateTime(2026, 9, 30, 20, 0));
  final fake = access ?? FakeAccess(testClock);
  final memory = store ?? MemorySessionStore();
  final container = ProviderContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(memory),
      adminClockProvider.overrideWithValue(() => testClock.now),
      accessRepositoryProvider.overrideWithValue(fake),
      // Sin red en los tests: la mesa de casos es falsa salvo que el test traiga la suya
      casesRepositoryProvider.overrideWithValue(cases ?? FakeCases(testClock)),
      todayRepositoryProvider.overrideWithValue(today ?? FakeToday()),
      tenantsRepositoryProvider.overrideWithValue(tenants ?? FakeTenants()),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AdminApp()));
  await tester.pumpAndSettle();
  return AdminTestApp(container, memory, testClock, fake);
}

/// Contraseña y código correctos.
Future<void> signIn(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('accessEmail')), 'eduardo@nexus.mx');
  await tester.enterText(find.byKey(const Key('accessPassword')), 'correcta');
  await tester.tap(find.byKey(const Key('accessSubmit')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('accessCodeField')), '123456');
  await tester.pumpAndSettle();
}

/// Almacén de pestaña con una sesión ya abierta (de "Eduardo Cristancho",
/// 2 h desde el reloj del test): el panel arranca dentro.
MemorySessionStore signedInStore(TestClock clock, {Duration left = const Duration(hours: 2)}) {
  final store = MemorySessionStore();
  store.write(
    AdminSessionNotifier.storageKey,
    jsonEncode(AdminSession(
      token: 'sesion-test',
      expiresAt: clock.now.add(left),
      operatorName: 'Eduardo Cristancho',
      operatorEmail: 'eduardo@nexus.mx',
      recoveryCodesRemaining: 10,
    ).toJson()),
  );
  return store;
}
