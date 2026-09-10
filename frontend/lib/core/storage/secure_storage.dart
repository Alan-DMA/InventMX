import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper sobre flutter_secure_storage para persistir tokens JWT
/// en el Keystore (Android) / Keychain (iOS).
///
/// Los tokens NO se guardan en Hive plano — decisión técnica D1.
/// Constitución Art. VIII (Sección 8.2: No almacenar contraseñas/tokens en texto plano)
class SecureStorage {
  SecureStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _keyAccessToken = 'nexus_access_token';
  static const _keyRefreshToken = 'nexus_refresh_token';

  // ---------- Access Token ----------

  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _keyAccessToken, value: token);

  Future<String?> readAccessToken() =>
      _storage.read(key: _keyAccessToken);

  // ---------- Refresh Token ----------

  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _keyRefreshToken, value: token);

  Future<String?> readRefreshToken() =>
      _storage.read(key: _keyRefreshToken);

  // ---------- Par completo ----------

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      saveAccessToken(accessToken),
      saveRefreshToken(refreshToken),
    ]);
  }

  /// Borra ambos tokens. Se llama al hacer logout o cuando el refresh falla.
  Future<void> clearAll() => _storage.deleteAll();

  /// Devuelve true si existe un access token guardado (no valida expiración).
  Future<bool> hasSession() async {
    final token = await readAccessToken();
    return token != null && token.isNotEmpty;
  }
}
