import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';

import '_harness.dart';

/// Fase actual (Sep 2026) — `AuthRepositoryImpl` es 100% real, sin gaps.
/// Requiere el backend levantado en 127.0.0.1:8000 (ver
/// docs/architecture/registro_implementacion.md, "Cómo levantar el entorno").
void main() {
  late bool backendUp;

  setUpAll(() async {
    await setUpTestHive();
    backendUp = await isBackendUp();
  });

  tearDownAll(() async {
    await tearDownTestHive();
  });

  group('AuthRepositoryImpl — contra backend real', () {
    test('register + login del tenant dedicado a integración', () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final hasSession = await session.storage.hasSession();
      expect(hasSession, isTrue);

      final token = await session.storage.readAccessToken();
      expect(token, isNotNull);
      expect(token, isNotEmpty);
    });

    test('login con contraseña incorrecta lanza AuthException', () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final storage = SecureStorage();
      final client = DioClient(baseUrl: integrationBaseUrl, storage: storage);
      final auth = AuthRepositoryImpl(client: client, storage: storage);

      // Primero garantiza que el tenant exista (idempotente).
      await signInIntegrationTenant();

      expect(
        () => auth.login(
          email: integrationTestEmail,
          password: 'contraseña-incorrecta',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('logout limpia la sesión guardada', () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      expect(await session.storage.hasSession(), isTrue);

      final auth = AuthRepositoryImpl(
        client: session.client,
        storage: session.storage,
      );
      await auth.logout();

      expect(await session.storage.hasSession(), isFalse);
    });

    test(
        'fetchDefaultWarehouseId/setDefaultWarehouseId persisten en el perfil real',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final auth = AuthRepositoryImpl(
        client: session.client,
        storage: session.storage,
      );
      final warehouseId = await fetchDefaultWarehouseId(session.client);

      await auth.setDefaultWarehouseId(warehouseId);

      expect(await auth.fetchDefaultWarehouseId(), warehouseId);

      // Un id de otro comercio (o inexistente) se rechaza — no se puede
      // operar en un almacén ajeno.
      expect(
        () => auth.setDefaultWarehouseId(
            '00000000-0000-0000-0000-000000000000'),
        throwsA(isA<AuthException>()),
      );
    });
  });
}
