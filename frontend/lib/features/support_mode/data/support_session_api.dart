import 'package:dio/dio.dart';

import '../domain/support_session.dart';

/// La sesión de soporte del lado de la pestaña: `/api/v1/support-session`.
/// Dio propio y sin el interceptor de la app: aquí cada respuesta se lee para
/// decir qué pasó, no para cerrar sesión.
abstract class SupportSessionApi {
  /// Canjea el código del enlace: devuelve el token y el estado.
  Future<(String, SupportSessionStatus)> open(String code);
  Future<SupportSessionStatus> status(String token);

  /// +30 min; devuelve un token nuevo.
  Future<(String, SupportSessionStatus)> extend(String token);
  Future<void> end(String token);
}

class SupportSessionApiImpl implements SupportSessionApi {
  SupportSessionApiImpl({required String baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            ));

  final Dio _dio;
  static const _path = '/api/v1/support-session';

  Options _auth(String token) => Options(headers: {'Authorization': 'Bearer $token'});

  @override
  Future<(String, SupportSessionStatus)> open(String code) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('$_path/open', data: {'code': code});
      return _opened(res.data);
    } on DioException catch (e) {
      throw _problem(e);
    }
  }

  @override
  Future<SupportSessionStatus> status(String token) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_path, options: _auth(token));
      return SupportSessionStatus.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _problem(e);
    }
  }

  @override
  Future<(String, SupportSessionStatus)> extend(String token) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('$_path/extend', options: _auth(token));
      return _opened(res.data);
    } on DioException catch (e) {
      throw _problem(e);
    }
  }

  @override
  Future<void> end(String token) async {
    try {
      await _dio.post<void>('$_path/end', options: _auth(token));
    } on DioException catch (_) {
      // Terminar no falla hacia el operador: la pestaña se limpia igual
    }
  }

  static (String, SupportSessionStatus) _opened(Map<String, dynamic>? data) {
    final body = data ?? const {};
    final status = body['status'];
    return ('${body['access_token'] ?? ''}', SupportSessionStatus.fromJson(status is Map ? status : const {}));
  }

  static Object _problem(DioException e) {
    final dynamic data = e.response?.data;
    final dynamic error = data is Map ? data['error'] : null;
    final code = error is Map ? '${error['code']}' : null;
    final message = error is Map ? '${error['message']}' : null;
    if (code == 'SUPPORT_ACCESS_ENDED' || e.response?.statusCode == 401) {
      final dynamic details = error is Map ? error['details'] : null;
      return SupportSessionEnded(SupportEnd.fromCode(details is Map ? '${details['end_reason']}' : null));
    }
    if (code == 'SUPPORT_LINK_INVALID' || code == 'SUPPORT_LINK_EXPIRED') {
      return SupportLinkProblem(message ?? 'Este enlace ya no sirve. Ábrelo de nuevo desde el panel.');
    }
    if (code == 'SUPPORT_SESSION_CONFLICT' && message != null) {
      return SupportLinkProblem(message);
    }
    if (e.response == null) {
      return const SupportLinkProblem('No pudimos conectar con el servidor. Revisa tu conexión y vuelve a intentar.');
    }
    return SupportLinkProblem(message ?? 'Algo salió mal al abrir la sesión de soporte.');
  }
}
