import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Wrapper sobre flutter_secure_storage para persistir tokens JWT
/// en el Keystore (Android) / Keychain (iOS) con soporte robusto para Flutter Web.
class SecureStorage {
  SecureStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _keyAccessToken = 'nexus_access_token';
  static const _keyRefreshToken = 'nexus_refresh_token';
  static const _keyUserEmail = 'nexus_user_email';
  static const _webAuthBoxName = 'web_secure_auth_store';

  Future<Box<dynamic>?> _getWebBox() async {
    try {
      if (Hive.isBoxOpen(_webAuthBoxName)) {
        return Hive.box<dynamic>(_webAuthBoxName);
      }
      return await Hive.openBox<dynamic>(_webAuthBoxName);
    } catch (_) {
      return null;
    }
  }

  // ---------- Access Token ----------

  Future<void> saveAccessToken(String token) async {
    try {
      if (!kIsWeb) {
        await _storage.write(key: _keyAccessToken, value: token);
        return;
      }
    } catch (_) {}
    // Fallback para Flutter Web o entornos HTTP LAN
    final box = await _getWebBox();
    await box?.put(_keyAccessToken, token);
  }

  Future<String?> readAccessToken() async {
    try {
      if (!kIsWeb) {
        final val = await _storage.read(key: _keyAccessToken);
        if (val != null && val.isNotEmpty) return val;
      }
    } catch (_) {}
    // Fallback para Flutter Web o entornos HTTP LAN
    final box = await _getWebBox();
    final dynamic val = box?.get(_keyAccessToken);
    return val?.toString();
  }

  // ---------- Refresh Token ----------

  Future<void> saveRefreshToken(String token) async {
    try {
      if (!kIsWeb) {
        await _storage.write(key: _keyRefreshToken, value: token);
        return;
      }
    } catch (_) {}
    // Fallback para Flutter Web o entornos HTTP LAN
    final box = await _getWebBox();
    await box?.put(_keyRefreshToken, token);
  }

  Future<String?> readRefreshToken() async {
    try {
      if (!kIsWeb) {
        final val = await _storage.read(key: _keyRefreshToken);
        if (val != null && val.isNotEmpty) return val;
      }
    } catch (_) {}
    // Fallback para Flutter Web o entornos HTTP LAN
    final box = await _getWebBox();
    final dynamic val = box?.get(_keyRefreshToken);
    return val?.toString();
  }

  // ---------- Correo de la sesión ----------

  /// Se guarda junto a los tokens porque al reabrir la app la sesión se
  /// restaura pero el correo no viajaba: la identidad caía en un valor por
  /// defecto y "Mi cuenta" mostraba a otra persona.
  Future<void> saveUserEmail(String email) async {
    try {
      if (!kIsWeb) {
        await _storage.write(key: _keyUserEmail, value: email);
        return;
      }
    } catch (_) {}
    final box = await _getWebBox();
    await box?.put(_keyUserEmail, email);
  }

  Future<String?> readUserEmail() async {
    try {
      if (!kIsWeb) {
        final val = await _storage.read(key: _keyUserEmail);
        if (val != null && val.isNotEmpty) return val;
      }
    } catch (_) {}
    final box = await _getWebBox();
    final dynamic val = box?.get(_keyUserEmail);
    return val?.toString();
  }

  // ---------- Par completo ----------

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await saveAccessToken(accessToken);
    await saveRefreshToken(refreshToken);
  }

  /// Borra **sólo las llaves de sesión** (tokens y correo).
  ///
  /// Antes borraba todo el almacén (`deleteAll`), lo que tiraba también las
  /// preferencias locales de cada persona: quien cerraba sesión perdía sus
  /// accesos rápidos y sus avisos leídos. Desde el QA de Eduardo (Sep 23)
  /// esas preferencias van con el correo en la clave y sobreviven al logout
  /// sin mezclarse entre usuarios (`scopedKey`).
  Future<void> clearSession() async {
    for (final key in const [_keyAccessToken, _keyRefreshToken, _keyUserEmail]) {
      try {
        if (!kIsWeb) await _storage.delete(key: key);
      } catch (_) {}
      final box = await _getWebBox();
      await box?.delete(key);
    }
  }

  /// Borra **todo** el almacén, preferencias incluidas. Sólo para reinicios
  /// de fábrica o diagnóstico; el logout usa [clearSession].
  Future<void> clearAll() async {
    try {
      if (!kIsWeb) {
        await _storage.deleteAll();
      }
    } catch (_) {}
    final box = await _getWebBox();
    await box?.clear();
  }

  /// Clave de una preferencia **con dueño**: la misma preferencia guardada
  /// por dos personas en el mismo teléfono no se pisa. Sin sesión resuelta
  /// cae en un espacio anónimo que nadie más lee.
  static String scopedKey(String key, String? owner) =>
      '$key::${(owner ?? '').trim().toLowerCase()}';

  /// Devuelve true si existe un access token guardado (no valida expiración).
  Future<bool> hasSession() async {
    final token = await readAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Escritura genérica de preferencia o clave local.
  Future<void> write(String key, String value) async {
    try {
      if (!kIsWeb) {
        await _storage.write(key: key, value: value);
        return;
      }
    } catch (_) {
      return;
    }
    try {
      final box = await _getWebBox();
      await box?.put(key, value);
    } catch (_) {}
  }

  /// Lectura genérica de preferencia o clave local.
  Future<String?> read(String key) async {
    try {
      if (!kIsWeb) {
        return await _storage.read(key: key);
      }
    } catch (_) {
      return null;
    }
    try {
      final box = await _getWebBox();
      final dynamic val = box?.get(key);
      return val?.toString();
    } catch (_) {
      return null;
    }
  }
}
