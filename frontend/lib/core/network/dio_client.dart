import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';
import 'auth_interceptor.dart';

/// Cliente HTTP centralizado de Nexus.
///
/// - Base URL configurable por entorno.
/// - Timeouts conservadores para VPS económico (Hetzner/Contabo).
/// - Inyecta AuthInterceptor para manejo automático de JWT.
/// - Registra errores de red sin exponer datos sensibles en logs.
class DioClient {
  DioClient({
    required String baseUrl,
    required SecureStorage storage,
    Future<void> Function()? onLogout,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.addAll([
      AuthInterceptor(storage: storage, dio: _dio, onLogout: onLogout),
      _buildLogInterceptor(),
    ]);
  }

  late final Dio _dio;

  /// Expone la instancia de Dio para los repositorios.
  Dio get instance => _dio;

  // ---------- Helpers de conveniencia ----------

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _dio.get<T>(path, queryParameters: queryParameters, options: options);

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Options? options,
  }) =>
      _dio.post<T>(path, data: data, options: options);

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Options? options,
  }) =>
      _dio.put<T>(path, data: data, options: options);

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Options? options,
  }) =>
      _dio.patch<T>(path, data: data, options: options);

  Future<Response<T>> delete<T>(
    String path, {
    Options? options,
  }) =>
      _dio.delete<T>(path, options: options);

  // ---------- Logging ----------

  LogInterceptor _buildLogInterceptor() {
    return LogInterceptor(
      requestBody: false,   // No loguear cuerpos — pueden contener credenciales
      responseBody: false,
      requestHeader: false, // No loguear headers — contienen Bearer tokens
      error: true,
      logPrint: (obj) {
        // En producción esto se reemplaza por un logger estructurado.
        // ignore: avoid_print
        assert(() {
          // ignore: avoid_print
          print('[DioClient] $obj');
          return true;
        }());
      },
    );
  }
}
