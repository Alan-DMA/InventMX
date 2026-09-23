import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/dashboard/domain/quick_action_item.dart';
import 'package:nexus_app/features/dashboard/presentation/quick_actions_preference.dart';

// ---------------------------------------------------------------------------
// Preferencias locales con dueño — QA de Eduardo (Sep 23, 2026)
// ---------------------------------------------------------------------------
//
// En el teléfono de mostrador entran varias personas. Los accesos rápidos que
// configuraba el cajero le aparecían al dueño: la clave era global y, peor, el
// notifier seguía vivo entre sesiones con el estado del anterior. Ahora la
// preferencia lleva el correo en la clave y el notifier observa quién está en
// sesión, así que se reconstruye al cambiar de usuario.

class _MemoryStorage extends SecureStorage {
  final Map<String, String> values = {};

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> clearSession() async {}
}

ProviderContainer _containerFor(String? email, SecureStorage storage) {
  final container = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      currentUserNameProvider.overrideWith((ref) => email),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('cada correo guarda sus accesos rápidos sin pisar los del otro',
      () async {
    final storage = _MemoryStorage();

    final cajero = _containerFor('carlos@gmail.com', storage);
    await cajero
        .read(quickActionsProvider.notifier)
        .setActions([QuickActionId.sell]);

    final dueno = _containerFor('eduardo@nexus.com', storage);
    await dueno
        .read(quickActionsProvider.notifier)
        .setActions([QuickActionId.gondola, QuickActionId.importExcel]);

    // Dos entradas distintas en el mismo almacén del teléfono.
    expect(storage.values.keys.toList()..sort(), [
      'nexus_preferred_quick_actions::carlos@gmail.com',
      'nexus_preferred_quick_actions::eduardo@nexus.com',
    ]);
    expect(storage.values['nexus_preferred_quick_actions::carlos@gmail.com'],
        'sell');
    expect(storage.values['nexus_preferred_quick_actions::eduardo@nexus.com'],
        'gondola,importExcel');
  });

  test('al volver a entrar, cada quien recupera lo suyo', () async {
    final storage = _MemoryStorage()
      ..values['nexus_preferred_quick_actions::carlos@gmail.com'] = 'sell'
      ..values['nexus_preferred_quick_actions::eduardo@nexus.com'] =
          'gondola,importExcel';

    final cajero = _containerFor('carlos@gmail.com', storage);
    cajero.listen(quickActionsProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    expect(cajero.read(quickActionsProvider), [QuickActionId.sell]);

    final dueno = _containerFor('eduardo@nexus.com', storage);
    dueno.listen(quickActionsProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    expect(dueno.read(quickActionsProvider),
        [QuickActionId.gondola, QuickActionId.importExcel]);
  });

  test('el correo va en la clave, y sin sesión cae en un espacio aparte', () {
    expect(SecureStorage.scopedKey('pref', 'Carlos@Gmail.com '),
        'pref::carlos@gmail.com');
    expect(SecureStorage.scopedKey('pref', null), 'pref::');
  });
}
