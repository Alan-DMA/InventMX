import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/admin_http.dart';
import '../domain/audit_models.dart';

/// Bitácora de la plataforma (sólo lectura; nadie la puede alterar desde la app).
abstract class AuditRepository {
  /// GET /platform/audit
  Future<AuditPage> list({
    String? action,
    String? tenantId,
    String? operatorId,
    bool excludeNoise = true,
    int limit = 50,
    int offset = 0,
  });

  /// GET /platform/audit/verify — recalcula la cadena de hashes.
  Future<ChainVerification> verify();
}

class AuditRepositoryImpl implements AuditRepository {
  AuditRepositoryImpl(this._dio);
  final Dio _dio;

  @override
  Future<AuditPage> list({
    String? action,
    String? tenantId,
    String? operatorId,
    bool excludeNoise = true,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final res = await _dio.get('/audit', queryParameters: {
        if (action != null) 'action': action,
        if (tenantId != null) 'tenant_id': tenantId,
        if (operatorId != null) 'operator_id': operatorId,
        'exclude_noise': excludeNoise,
        'limit': limit,
        'offset': offset,
      });
      final json = res.data as Map<String, dynamic>;
      return AuditPage(
        items: [for (final e in json['items'] as List) AuditEntry.fromJson(e as Map<String, dynamic>)],
        total: (json['total'] as num).toInt(),
      );
    } catch (e) {
      throw toAdminError(e, 'No pudimos cargar la bitácora.');
    }
  }

  @override
  Future<ChainVerification> verify() async {
    try {
      final res = await _dio.get('/audit/verify');
      final json = res.data as Map<String, dynamic>;
      return ChainVerification(
        intact: json['intact'] == true,
        checked: (json['checked'] as num?)?.toInt() ?? 0,
        brokenAtId: (json['broken_at_id'] as num?)?.toInt(),
      );
    } catch (e) {
      throw toAdminError(e, 'No pudimos verificar la bitácora.');
    }
  }
}

final auditRepositoryProvider = Provider<AuditRepository>((ref) => AuditRepositoryImpl(ref.watch(adminDioProvider)));
