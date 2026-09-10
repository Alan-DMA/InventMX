import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';

/// Interceptor JWT de Nexus.
///
/// Responsabilidades:
///   1. Adjunta `Authorization: Bearer <accessToken>` en cada request saliente.
///   2. Ante un 401, intenta renovar el access token usando el refresh token.
///   3. Si el refresh también falla, limpia la sesión y emite el error para
///      que GoRouter redirija al Login.
///
/// CA-06: Bearer adjunto en cada request
/// CA-07: Refresh ante 401 antes de logout
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.storage,
    required this.dio,
    this.onLogout,
  });

  final SecureStorage storage;

  /// Instancia de Dio — se inyecta desde DioClient para evitar referencias
  /// circulares al crear un cliente secundario para el refresh.
  final Dio dio;

  /// Callback opcional que el router/provider llama para limpiar estado
  /// de autenticación en Riverpod cuando el refresh falla.
  final Future<void> Function()? onLogout;

  // Evita reintentos infinitos si el propio endpoint de refresh devuelve 401.
  static const _retryHeader = 'X-Retry-Request';

  // ---------- Request ----------

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await storage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  // ---------- Error (401 → refresh) ----------

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;

    // Solo actuamos ante 401 y si no es ya un reintento
    if (response?.statusCode != 401 ||
        err.requestOptions.headers.containsKey(_retryHeader)) {
      handler.next(err);
      return;
    }

    final refreshToken = await storage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _handleLogout(handler, err);
      return;
    }

    try {
      // Petición de refresh usando una instancia limpia para no re-disparar
      // este interceptor (cabecera _retryHeader actúa como flag).
      final refreshDio = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
      final refreshResponse = await refreshDio.post(
        '/api/v1/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(headers: {_retryHeader: 'true'}),
      );

      final newAccessToken =
          refreshResponse.data['access_token'] as String? ?? '';
      final newRefreshToken =
          refreshResponse.data['refresh_token'] as String? ?? '';

      if (newAccessToken.isEmpty) {
        await _handleLogout(handler, err);
        return;
      }

      await storage.saveTokens(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken.isNotEmpty ? newRefreshToken : refreshToken,
      );

      // Reintenta la petición original con el nuevo token
      final retryOptions = err.requestOptions
        ..headers['Authorization'] = 'Bearer $newAccessToken'
        ..headers[_retryHeader] = 'true';

      final retryResponse = await dio.fetch(retryOptions);
      handler.resolve(retryResponse);
    } on DioException {
      await _handleLogout(handler, err);
    }
  }

  // ---------- Helpers ----------

  Future<void> _handleLogout(
    ErrorInterceptorHandler handler,
    DioException err,
  ) async {
    await storage.clearAll();
    await onLogout?.call();
    handler.next(err);
  }
}
