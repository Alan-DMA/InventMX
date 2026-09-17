/// La contraseña actual no coincide con la que tiene el usuario.
class WrongCurrentPasswordException implements Exception {
  const WrongCurrentPasswordException();

  String get message => 'La contraseña actual no es correcta.';

  @override
  String toString() => message;
}

/// Datos propios de quien está en sesión que no son del negocio.
///
/// Hoy sólo la contraseña. El backend legacy **no expone** cambio de
/// contraseña (`app/api/v1/auth.py` sólo tiene login y refresh): queda
/// propuesto `POST /api/v1/auth/change-password` con `{current_password,
/// new_password}` y 400 si la actual no coincide. Mientras tanto, mock.
abstract class AccountRepository {
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

class AccountRepositoryMock implements AccountRepository {
  AccountRepositoryMock({this.knownPassword = 'Cajero123'});

  /// La que el mock acepta como "actual". Coincide con la del usuario
  /// sembrado en `backend/app/seed.py` para que el QA en dispositivo se
  /// sienta real.
  String knownPassword;

  static const _fakeDelay = Duration(milliseconds: 500);

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await Future.delayed(_fakeDelay);
    if (currentPassword != knownPassword) {
      throw const WrongCurrentPasswordException();
    }
    knownPassword = newPassword;
  }
}
