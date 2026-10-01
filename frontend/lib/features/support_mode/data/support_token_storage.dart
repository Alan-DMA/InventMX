import '../../../core/storage/secure_storage.dart';
import 'tab_browser.dart';

/// El almacenamiento de la app del tendero dentro de la pestaña de soporte.
///
/// El token de la sesión vive en la pestaña ([TabBrowser], `sessionStorage`);
/// todo lo demás que la app quiera guardar (preferencias, banderas) se queda
/// en memoria y se pierde al cerrar. No hay refresh: al vencer la sesión no
/// se renueva sola, se extiende desde la franja o se termina.
class SupportTokenStorage extends SecureStorage {
  SupportTokenStorage(this.tab);

  final TabBrowser tab;
  final Map<String, String> _memory = {};

  @override
  Future<String?> readAccessToken() async => tab.readToken();

  @override
  Future<void> saveAccessToken(String token) async => tab.writeToken(token);

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> saveRefreshToken(String token) async {}

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async =>
      tab.writeToken(accessToken);

  @override
  Future<void> saveUserEmail(String email) async {}

  @override
  Future<String?> readUserEmail() async => null;

  @override
  Future<void> saveMustChangePassword(bool value) async {}

  @override
  Future<bool> readMustChangePassword() async => false;

  @override
  Future<bool> hasSession() async => (tab.readToken() ?? '').isNotEmpty;

  /// La app no cierra la sesión de soporte por su cuenta: la termina la franja
  /// o el servidor. Un 401 sin refresh llega aquí y no debe borrar el token
  /// antes de que la franja lea por qué terminó.
  @override
  Future<void> clearSession() async {}

  @override
  Future<void> clearAll() async => _memory.clear();

  @override
  Future<void> write(String key, String value) async => _memory[key] = value;

  @override
  Future<String?> read(String key) async => _memory[key];
}
