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
  static const _webAuthBoxName = 'web_secure_auth_store';

  Future<Box<dynamic>> _getWebBox() async {
    if (Hive.isBoxOpen(_webAuthBoxName)) {
      return Hive.box<dynamic>(_webAuthBoxName);
    }
    return await Hive.openBox<dynamic>(_webAuthBoxName);
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
    await box.put(_keyAccessToken, token);
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
    final dynamic val = box.get(_keyAccessToken);
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
    await box.put(_keyRefreshToken, token);
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
    final dynamic val = box.get(_keyRefreshToken);
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

  /// Borra ambos tokens. Se llama al hacer logout o cuando el refresh falla.
  Future<void> clearAll() async {
    try {
      if (!kIsWeb) {
        await _storage.deleteAll();
      }
    } catch (_) {}
    final box = await _getWebBox();
    await box.clear();
  }

  /// Devuelve true si existe un access token guardado (no valida expiración).
  Future<bool> hasSession() async {
    final token = await readAccessToken();
    return token != null && token.isNotEmpty;
  }
}
