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
///
/// Además avisa a la app de dos señales del servidor (Centro de soporte):
/// `PASSWORD_CHANGE_REQUIRED` (403: entró con código y falta la contraseña
/// nueva) y `TENANT_HARD_LOCK` (402: la tienda se suspendió con la app
/// abierta). Quien escucha actualiza el estado y el router hace el resto.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.storage,
    required this.dio,
    this.onLogout,
    this.onServerSignal,
  });

  /// Señales que la app escucha en [onServerSignal].
  static const passwordChangeRequired = 'PASSWORD_CHANGE_REQUIRED';
  static const tenantHardLock = 'TENANT_HARD_LOCK';
  // Sesión de soporte de sólo lectura (etapa 4): la pestaña de soporte las atiende
  static const supportAccessEnded = 'SUPPORT_ACCESS_ENDED';
  static const supportReadOnly = 'SUPPORT_READ_ONLY';
  static const supportNotAllowed = 'SUPPORT_NOT_ALLOWED';
  static const _signals = {
    passwordChangeRequired, tenantHardLock, supportAccessEnded, supportReadOnly, supportNotAllowed,
  };

  final SecureStorage storage;

  /// Instancia de Dio — se inyecta desde DioClient para evitar referencias
  /// circulares al crear un cliente secundario para el refresh.
  final Dio dio;

  /// Callback opcional que el router/provider llama para limpiar estado
  /// de autenticación en Riverpod cuando el refresh falla.
  final Future<void> Function()? onLogout;

  /// Recibe el código de error de un 402/403 que la app debe atender.
  final void Function(String code)? onServerSignal;

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

    final signal = _signalOf(response);
    if (signal != null) onServerSignal?.call(signal);

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

  /// Código de la señal, o null. `SUPPORT_ACCESS_ENDED` lleva el motivo:
  /// `SUPPORT_ACCESS_ENDED:GRANT_ENDED`.
  static String? _signalOf(Response<dynamic>? response) {
    final status = response?.statusCode;
    if (status != 401 && status != 402 && status != 403) return null;
    final dynamic data = response?.data;
    final dynamic error = data is Map ? data['error'] : null;
    final code = error is Map ? error['code']?.toString() : null;
    if (code == null || !_signals.contains(code)) return null;
    if (code == supportAccessEnded) {
      final dynamic details = error is Map ? error['details'] : null;
      final reason = details is Map ? details['end_reason']?.toString() : null;
      return reason == null ? code : '$code:$reason';
    }
    return code;
  }

  Future<void> _handleLogout(
    ErrorInterceptorHandler handler,
    DioException err,
  ) async {
    await storage.clearAll();
    await onLogout?.call();
    handler.next(err);
  }
}
