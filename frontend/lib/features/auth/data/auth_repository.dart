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

  /// GET /api/v1/auth/me — almacén operativo persistido en el perfil del
  /// usuario (`null` si nunca lo ha elegido). `null` también si falla la
  /// red: quien llama cae a un almacén por defecto, igual que ya hace
  /// `warehousesProvider` con la lista completa.
  Future<String?> fetchDefaultWarehouseId();

  /// PATCH /api/v1/auth/me/warehouse — cambia el almacén operativo del
  /// usuario en sesión (configurable desde su perfil, Doc. Maestro D6).
  Future<void> setDefaultWarehouseId(String warehouseId);
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

  @override
  Future<String?> fetchDefaultWarehouseId() async {
    try {
      final response = await client.get('/api/v1/auth/me');
      final dynamic data = response.data;
      if (data is Map) return data['default_warehouse_id']?.toString();
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setDefaultWarehouseId(String warehouseId) async {
    try {
      await client.patch(
        '/api/v1/auth/me/warehouse',
        data: {'warehouse_id': warehouseId},
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

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

  String? _defaultWarehouseId;

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

  @override
  Future<String?> fetchDefaultWarehouseId() async => _defaultWarehouseId;

  @override
  Future<void> setDefaultWarehouseId(String warehouseId) async {
    _defaultWarehouseId = warehouseId;
  }
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
