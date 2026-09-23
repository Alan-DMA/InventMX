import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';

// ---------------------------------------------------------------------------
// El correo de la sesión se persiste al entrar
// ---------------------------------------------------------------------------
//
// Encontrado en QA (Sep 16): al reabrir la app, `hasSession()` restauraba la
// sesión pero el correo no viajaba, así que `currentUserNameProvider` quedaba
// en null y la identidad caía en el valor por defecto del mock — "Mi cuenta"
// mostraba a otra persona, y el ticket y las comisiones un cajero genérico.

class _FakeStorage extends SecureStorage {
  String? savedEmail;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> saveUserEmail(String email) async => savedEmail = email;

  @override
  Future<String?> readUserEmail() async => savedEmail;

  @override
  Future<void> clearSession() async => savedEmail = null;

  @override
  Future<void> clearAll() async => savedEmail = null;
}

void main() {
  test('entrar guarda el correo para la próxima apertura', () async {
    final storage = _FakeStorage();
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authRepositoryProvider
            .overrideWithValue(AuthRepositoryMock(storage: storage)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(loginProvider.notifier).login(
          email: 'demo@nexus.mx',
          password: 'nexus123',
        );

    expect(container.read(sessionProvider), isTrue);
    expect(container.read(currentUserNameProvider), 'demo@nexus.mx');
    // Lo que faltaba: que sobreviva al cierre de la app.
    expect(await storage.readUserEmail(), 'demo@nexus.mx');
  });

  test('salir borra el correo junto con los tokens', () async {
    final storage = _FakeStorage()..savedEmail = 'demo@nexus.mx';
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authRepositoryProvider
            .overrideWithValue(AuthRepositoryMock(storage: storage)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(loginProvider.notifier).logout();

    expect(container.read(sessionProvider), isFalse);
    expect(container.read(currentUserNameProvider), isNull);
    expect(await storage.readUserEmail(), isNull);
  });

  test('credenciales incorrectas no dejan correo guardado', () async {
    final storage = _FakeStorage();
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authRepositoryProvider
            .overrideWithValue(AuthRepositoryMock(storage: storage)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(loginProvider.notifier).login(
          email: 'otro@nexus.mx',
          password: 'equivocada',
        );

    expect(container.read(loginProvider).hasError, isTrue);
    expect(await storage.readUserEmail(), isNull);
  });
}
