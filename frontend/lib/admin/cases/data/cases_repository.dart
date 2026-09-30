import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/admin_http.dart';
import '../domain/desk_case.dart';

/// Mesa de casos del panel (`/platform/cases`). Los errores salen como
/// [AdminApiException].
abstract class CasesRepository {
  /// Esperando: lo más antiguo primero (P31); lo demás, lo reciente primero.
  Future<DeskCasePage> list({required DeskCaseStatus status, String? query, int limit = 30, int offset = 0});

  /// Cuántos esperan respuesta (el contador de la navegación).
  Future<int> waitingCount();

  Future<DeskCaseDetail> detail(String id);

  /// Los casos de una tienda (todos los estados), para su ficha.
  Future<List<DeskCase>> forTenant(String tenantId, {int limit = 10});

  Future<DeskCaseDetail> reply(String id, String body, {bool resolve = false});

  Future<DeskCaseDetail> setStatus(String id, DeskCaseStatus status);
}

class CasesRepositoryImpl implements CasesRepository {
  CasesRepositoryImpl(this._dio);
  final Dio _dio;

  @override
  Future<DeskCasePage> list({required DeskCaseStatus status, String? query, int limit = 30, int offset = 0}) async {
    try {
      final res = await _dio.get('/cases', queryParameters: {
        'status': status.api,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'limit': limit,
        'offset': offset,
      });
      return DeskCasePage.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw toAdminError(e, 'No pudimos cargar los casos.');
    }
  }

  @override
  Future<int> waitingCount() async {
    final page = await list(status: DeskCaseStatus.waiting, limit: 1);
    return page.total;
  }

  @override
  Future<List<DeskCase>> forTenant(String tenantId, {int limit = 10}) async {
    try {
      final res = await _dio.get('/cases', queryParameters: {'tenant_id': tenantId, 'limit': limit});
      return DeskCasePage.fromJson(res.data as Map<String, dynamic>).items;
    } catch (e) {
      throw toAdminError(e, 'No pudimos cargar los casos de la tienda.');
    }
  }

  @override
  Future<DeskCaseDetail> detail(String id) => _detail(() => _dio.get('/cases/$id'), 'No pudimos abrir el caso.');

  @override
  Future<DeskCaseDetail> reply(String id, String body, {bool resolve = false}) => _detail(
        () => _dio.post('/cases/$id/messages', data: {'body': body, 'resolve': resolve}),
        'No se envió la respuesta.',
      );

  @override
  Future<DeskCaseDetail> setStatus(String id, DeskCaseStatus status) => _detail(
        () => _dio.post('/cases/$id/status', data: {'status': status.api}),
        'No se cambió el estado.',
      );

  Future<DeskCaseDetail> _detail(Future<Response<dynamic>> Function() call, String fallback) async {
    try {
      final res = await call();
      return DeskCaseDetail.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw toAdminError(e, fallback);
    }
  }
}

final casesRepositoryProvider = Provider<CasesRepository>((ref) => CasesRepositoryImpl(ref.watch(adminDioProvider)));
