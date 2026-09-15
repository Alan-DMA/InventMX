import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../domain/auth_token.dart';

/// Contrato del repositorio de autenticación.
abstract class AuthRepository {
  Future<AuthToken> login({
    required String email,
    required String password,
  });

  Future<void> logout();

  Future<bool> hasSession();
}

// ---------------------------------------------------------------------------
// Implementación real (conecta con POST /api/v1/auth/login)
// ---------------------------------------------------------------------------

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({required this.client, required this.storage});

  final DioClient client;
  final SecureStorage storage;

  @override
  Future<AuthToken> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await client.post(
        '/api/v1/auth/login',
        data: {
          'username_or_email': email.trim(),
          'email': email.trim(),
          'password': password,
        },
      );

      final dynamic data = response.data;
      if (data == null || data is! Map) {
        throw const AuthException('Respuesta inválida del servidor.');
      }

      final token = AuthToken.fromJson(data);
      await storage.saveTokens(
        accessToken: token.accessToken,
        refreshToken: token.refreshToken,
      );
      return token;
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Error al autenticar: $e');
    }
  }

  @override
  Future<void> logout() => storage.clearAll();

  @override
  Future<bool> hasSession() => storage.hasSession();

  Exception _mapDioError(DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map) {
        if (data['error'] is Map && data['error']['message'] != null) {
          return AuthException(data['error']['message'].toString());
        }
        if (data['detail'] != null) {
          return AuthException(data['detail'].toString());
        }
      }
    }

    switch (e.response?.statusCode) {
      case 401:
        return const AuthException('Correo o contraseña incorrectos.');
      case 422:
        return const AuthException('Datos de acceso inválidos.');
      case 503:
        return const AuthException(
            'Servidor no disponible. Intenta más tarde.');
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          return const AuthException('Sin conexión con el servidor. Verifica tu red.');
        }
        return AuthException('Error de comunicación: ${e.message ?? e.type.name}');
    }
  }
}

// ---------------------------------------------------------------------------
// Mock — activo durante Tarea 1.2 (backend Alan aún no disponible)
// Persiste tokens en SecureStorage para que sessionProvider reaccione.
// ---------------------------------------------------------------------------

class AuthRepositoryMock implements AuthRepository {
  AuthRepositoryMock({required this.storage});

  final SecureStorage storage;

  static const _validEmail = 'demo@nexus.mx';
  static const _validPassword = 'nexus123';

  @override
  Future<AuthToken> login({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));

    if (email == _validEmail && password == _validPassword) {
      const token = AuthToken(
        accessToken: 'mock.access.token',
        refreshToken: 'mock.refresh.token',
      );
      // Persiste igual que la impl real para que el router reaccione.
      await storage.saveTokens(
        accessToken: token.accessToken,
        refreshToken: token.refreshToken,
      );
      return token;
    }
    throw const AuthException('Correo o contraseña incorrectos.');
  }

  @override
  Future<void> logout() => storage.clearAll();

  @override
  Future<bool> hasSession() => storage.hasSession();
}

// ---------------------------------------------------------------------------
// Excepción tipada de autenticación
// ---------------------------------------------------------------------------

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Providers de Riverpod
// ---------------------------------------------------------------------------

final secureStorageProvider = Provider<SecureStorage>(
  (_) => SecureStorage(),
);

/// Proveedor del cliente HTTP DioClient configurado con URL dinámica
final dioClientProvider = Provider<DioClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return DioClient(
    baseUrl: getEffectiveApiBaseUrl(),
    storage: storage,
  );
});

/// Repositorio de autenticación conectado al Backend real
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(
    client: ref.watch(dioClientProvider),
    storage: ref.watch(secureStorageProvider),
  ),
);
