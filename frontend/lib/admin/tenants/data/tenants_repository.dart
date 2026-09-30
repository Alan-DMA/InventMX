import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/admin_http.dart';
import '../domain/tenant_models.dart';

/// Tiendas en el panel: buscador y ficha (sólo metadatos, P2).
abstract class TenantsRepository {
  /// GET /platform/tenants?q= — nombre, slug o correo del dueño.
  Future<List<TenantSummary>> search(String query, {int limit = 20});

  /// GET /platform/tenants/{id} — abrirla queda en la bitácora.
  Future<TenantDetail> detail(String id);
}

class TenantsRepositoryImpl implements TenantsRepository {
  TenantsRepositoryImpl(this._dio);
  final Dio _dio;

  @override
  Future<List<TenantSummary>> search(String query, {int limit = 20}) async {
    try {
      final res = await _dio.get('/tenants', queryParameters: {'q': query.trim(), 'limit': limit});
      final items = (res.data as Map<String, dynamic>)['items'] as List;
      return [for (final t in items) TenantSummary.fromJson(t as Map<String, dynamic>)];
    } catch (e) {
      throw toAdminError(e, 'No pudimos buscar tiendas.');
    }
  }

  @override
  Future<TenantDetail> detail(String id) async {
    try {
      final res = await _dio.get('/tenants/$id');
      return TenantDetail.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw toAdminError(e, 'No pudimos abrir la ficha.');
    }
  }
}

final tenantsRepositoryProvider =
    Provider<TenantsRepository>((ref) => TenantsRepositoryImpl(ref.watch(adminDioProvider)));
