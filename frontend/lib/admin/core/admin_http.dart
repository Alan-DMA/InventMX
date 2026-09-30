import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart' show getEffectiveApiBaseUrl;
import '../session/admin_session.dart';

/// Un fallo del panel ya en palabras del operador. `statusCode` nulo = sin
/// respuesta del servidor (red).
class AdminApiException implements Exception {
  const AdminApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isNetwork => statusCode == null;

  @override
  String toString() => message;
}

const _networkMessage = 'Sin conexión con el servidor. Revisa tu red y vuelve a intentar.';
const _serverMessage = 'El servidor tuvo un problema. Intenta de nuevo en un momento.';

/// Traduce cualquier error de Dio a un [AdminApiException]. El backend
/// responde `{"detail": "..."}` (HTTPException) o `{"error": {"message",
/// "details"}}` (excepciones propias y validación); se usa el texto del
/// servidor cuando lo hay, que ya está escrito para el operador.
AdminApiException toAdminError(Object error, String fallback) {
  if (error is AdminApiException) return error;
  if (error is! DioException) return AdminApiException(fallback);
  final response = error.response;
  if (response == null) return const AdminApiException(_networkMessage);
  final status = response.statusCode;
  if (status != null && status >= 500) return AdminApiException(_serverMessage, statusCode: status);
  return AdminApiException(_messageFrom(response.data) ?? fallback, statusCode: status);
}

String? _messageFrom(Object? data) {
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is String && detail.isNotEmpty) return detail;
  final error = data['error'];
  if (error is Map) {
    // Validación: el primer motivo concreto dice más que "Error de validación"
    final details = error['details'];
    if (details is List && details.isNotEmpty && details.first is Map) {
      final msg = (details.first as Map)['msg']?.toString() ?? '';
      if (msg.isNotEmpty) return msg.replaceFirst(RegExp(r'^Value error,\s*'), '');
    }
    final message = error['message'];
    if (message is String && message.isNotEmpty) return message;
  }
  return null;
}

/// Cliente del panel: `/api/v1/platform`, sin el interceptor del tendero (los
/// tokens no se cruzan, CA-P4). Adjunta el token de la sesión y, si el
/// servidor ya no lo acepta (401 fuera del acceso), da la sesión por vencida:
/// el router lleva al acceso y de regreso a donde estaba.
final adminDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: '${getEffectiveApiBaseUrl()}/api/v1/platform',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final session = ref.read(adminSessionProvider).session;
        if (session != null && !options.path.startsWith('/auth/')) {
          options.headers['Authorization'] = 'Bearer ${session.token}';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        final unauthorized = error.response?.statusCode == 401;
        if (unauthorized && !error.requestOptions.path.startsWith('/auth/')) {
          ref.read(adminSessionProvider.notifier).expire();
        }
        handler.next(error);
      },
    ),
  );
  return dio;
});
