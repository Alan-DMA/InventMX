import 'dart:convert' show latin1;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:nexus_app/core/network/auth_interceptor.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/saas_admin/data/saas_repository.dart';
import 'package:nexus_app/features/support/data/support_repository.dart';
import 'package:nexus_app/features/support/domain/support_models.dart';
import 'package:nexus_app/features/support_access/data/support_access_repository.dart';

import '_harness.dart';

/// Centro de soporte, etapa 2b — los repositorios reales contra el backend
/// vivo (temas servidos por el servidor, casos, formulario sin sesión,
/// recuperación y acceso de soporte). El código de recuperación sólo existe en
/// el correo: su recorrido completo lo prueba el QA del backend.
void main() {
  late bool backendUp;

  setUpAll(() async {
    await setUpTestHive();
    backendUp = await isBackendUp();
  });

  tearDownAll(() async {
    await tearDownTestHive();
  });

  group('Soporte — contra backend real', () {
    test('temas del dueño, abrir un caso, leerlo y resolverlo', () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }
      final session = await signInIntegrationTenant();
      final repo = SupportRepositoryImpl(client: session.client);

      final topics = await repo.topics();
      final keys = topics.map((t) => t.key).toList();
      expect(keys, containsAll(['subscription', 'my_data', 'something_broken', 'other']));
      expect(keys, isNot(contains('cannot_login')));
      final broken = topics.firstWhere((t) => t.key == 'something_broken');
      expect(broken.formFields.first.type, FormFieldType.select);
      expect(broken.blocks.any((b) => b.isList), isTrue);

      // El servidor valida contra el formulario del tema y lo dice en sus palabras
      await expectLater(
        repo.createCase(topicKey: 'something_broken', answers: {}, description: 'Falla al cobrar con tarjeta.'),
        throwsA(isA<SupportException>().having((e) => e.message, 'message', contains('Falta responder'))),
      );

      final created = await repo.createCase(
        topicKey: 'something_broken',
        answers: {'module': 'Ventas'},
        description: 'Falla al cobrar con tarjeta (prueba de integración).',
      );
      expect(created.number, greaterThanOrEqualTo(1001));
      expect(created.status, CaseStatus.waitingSupport);
      expect(created.answers.single.value, 'Ventas');
      expect(created.messages.single.fromSupport, isFalse);

      final mine = await repo.cases();
      expect(mine.map((c) => c.id), contains(created.id));
      expect(await repo.unreadCount(), 0);

      final replied = await repo.reply(created.id, 'Agrego: pasa sólo con tarjetas de débito.');
      expect(replied.messages, hasLength(2));
      final resolved = await repo.resolve(created.id);
      expect(resolved.status, CaseStatus.resolved);
    });

    test('sin sesión: temas públicos y formulario (misma respuesta siempre)', () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }
      final repo = SupportRepositoryImpl(
        client: DioClient(baseUrl: integrationBaseUrl, storage: SecureStorage()),
      );
      final topics = await repo.publicTopics();
      expect(topics.map((t) => t.key), ['cannot_login']);

      final message = await repo.createPublicCase(
        topicKey: 'cannot_login',
        answers: {'problem': 'No me llega el código'},
        description: 'Pido el código y no llega (prueba de integración).',
        accountEmail: integrationTestEmail,
        storeName: 'Tienda de Integración',
        contactEmail: 'integracion-contacto@nexus.mx',
      );
      expect(message, kPublicCaseAccepted);
    });

    test('recuperar contraseña responde igual exista o no el correo; código falso → mensaje claro', () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }
      final storage = SecureStorage();
      final auth = AuthRepositoryImpl(client: DioClient(baseUrl: integrationBaseUrl, storage: storage), storage: storage);
      final known = await auth.requestPasswordRecovery(integrationTestEmail);
      final unknown = await auth.requestPasswordRecovery('nadie-integracion@nexus.mx');
      expect(known, unknown);
      await expectLater(
        auth.loginWithCode(email: 'nadie-integracion@nexus.mx', code: 'AAAA-AAAA'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', kWrongCodeMessage)),
      );
    });

    // Sólo con el correo en consola del servidor de QA (`EMAIL_BACKEND=console`,
    // `ENVIRONMENT=development`) y su log: `--dart-define=QA_SERVER_LOG=<ruta>`.
    const serverLog = String.fromEnvironment('QA_SERVER_LOG');
    test('con un código válido: entra, el servidor exige contraseña nueva y al ponerla libera', () async {
      if (!backendUp || serverLog.isEmpty) {
        markTestSkipped('Requiere el servidor de QA y QA_SERVER_LOG');
        return;
      }
      await signInIntegrationTenant(); // asegura que el tenant exista
      final storage = SecureStorage();
      final signals = <String>[];
      final client = DioClient(baseUrl: integrationBaseUrl, storage: storage, onServerSignal: signals.add);
      final auth = AuthRepositoryImpl(client: client, storage: storage);

      await auth.requestPasswordRecovery(integrationTestEmail);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final log = await File(serverLog).readAsString(encoding: latin1); // consola de Windows
      final block = log.split('Correo (console) ').lastWhere((b) => b.split('\n').first.trim().endsWith(integrationTestEmail));
      final code = RegExp(r'\b([A-Z2-9]{4}-[A-Z2-9]{4})\b').firstMatch(block)!.group(1)!;

      final token = await auth.loginWithCode(email: integrationTestEmail, code: code);
      expect(token.mustChangePassword, isTrue);

      // Cualquier otra ruta: 403 y la señal que la app escucha
      await expectLater(client.get<dynamic>('/api/v1/inventory/products'), throwsA(isA<DioException>()));
      expect(signals, contains(AuthInterceptor.passwordChangeRequired));

      // La misma contraseña de siempre, para no romper los demás tests de integración
      await auth.setNewPassword(integrationTestPassword);
      final products = await client.get<dynamic>('/api/v1/inventory/products');
      expect(products.statusCode, 200);
      await expectLater(
        auth.loginWithCode(email: integrationTestEmail, code: code),
        throwsA(isA<AuthException>()),
      );
    });

    test('acceso de soporte: conceder y quitar; la suscripción activa no trae motivo de bloqueo', () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }
      final session = await signInIntegrationTenant();
      final access = SupportAccessRepositoryImpl(client: session.client);
      final granted = await access.grant(1);
      expect(granted.active, isNotNull);
      expect(granted.active!.expiresAt.difference(granted.active!.createdAt).inMinutes, closeTo(60, 1));
      final revoked = await access.revoke();
      expect(revoked.active, isNull);
      expect(revoked.history.first.revokedAt, isNotNull);

      final sub = await SaasRepositoryImpl(client: session.client).getSubscription();
      expect(sub.isAbuseSuspension, isFalse);
      expect(sub.lockReason, isNull);
    });
  });
}
