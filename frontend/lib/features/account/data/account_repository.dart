import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';

/// La contraseña actual no coincide con la que tiene el usuario.
class WrongCurrentPasswordException implements Exception {
  const WrongCurrentPasswordException();

  String get message => 'La contraseña actual no es correcta.';

  @override
  String toString() => message;
}

/// Datos propios de quien está en sesión que no son del negocio.
///
/// Hoy sólo la contraseña: `POST /api/v1/auth/change-password` con
/// `{current_password, new_password}` (Ajustes operativos, D9) — exige la
/// actual (400 si no coincide), mínimo 8, y la sesión sigue abierta.
abstract class AccountRepository {
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl({required this.client});

  final DioClient client;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await client.post('/api/v1/auth/change-password', data: {
        'current_password': currentPassword,
        'new_password': newPassword,
      });
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) {
        throw const WrongCurrentPasswordException();
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Sin conexión con el servidor. Revisa tu red.');
      }
      throw Exception('No se pudo cambiar la contraseña. Intenta de nuevo.');
    }
  }
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
