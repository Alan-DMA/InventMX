import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/admin_http.dart';
import '../domain/tenant_models.dart';

/// Acciones de soporte sobre una tienda (P16–P18): todas con motivo, que el
/// dueño lee en su app (P8). Los rechazos del servidor salen como
/// [AdminApiException] con su explicación.
enum PreviewAction {
  assistedRecovery('ASSISTED_RECOVERY_SENT'),
  giftDays('DAYS_GIFTED'),
  suspend('ABUSE_SUSPENDED'),
  lift('ABUSE_LIFTED'),
  export('DATA_EXPORT_REQUESTED'),
  deletion('TENANT_DELETION_REQUESTED');

  const PreviewAction(this.api);
  final String api;
}

/// "Así lo verá la tienda": el texto exacto del dueño, sin cambiar nada.
class OwnerPreview {
  const OwnerPreview({required this.summary, required this.by, this.reason});
  final String summary;
  final String? reason;
  final String by;
}

class RecoverySent {
  const RecoverySent({required this.sentTo, required this.expiresAt});

  /// Correo del dueño enmascarado: el operador nunca ve el código.
  final String sentTo;
  final DateTime expiresAt;
}

class DeletionRequestRead {
  const DeletionRequestRead(
      {required this.id, required this.expiresAt, this.requestedById, this.requestedBy, this.reason = ''});
  final String id;
  final String? requestedById;
  final String? requestedBy;
  final String reason;
  final DateTime expiresAt;

  factory DeletionRequestRead.fromJson(Map<String, dynamic> json) => DeletionRequestRead(
        id: json['id'].toString(),
        requestedById: json['requested_by']?.toString(),
        requestedBy: json['requested_by_name'] as String?,
        reason: (json['reason'] ?? '').toString(),
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

abstract class SupportActionsRepository {
  Future<OwnerPreview> preview(String tenantId, PreviewAction action, {String? reason, int? days});

  Future<RecoverySent> assistedRecovery(
    String tenantId, {
    required String reason,
    required Map<String, bool> checks,
    String? googleOrderId,
  });

  Future<TenantDetail> giftDays(String tenantId, {required int days, required String reason});

  Future<TenantDetail> suspend(String tenantId, {required String reason});

  Future<TenantDetail> lift(String tenantId, {required String reason});

  /// El archivo le llega al dueño por correo; aquí sólo el estado.
  Future<String> export(String tenantId, {required String reason});

  Future<DeletionRequestRead> requestDeletion(String tenantId, {required String reason, required String confirmSlug});

  Future<void> approveDeletion(String requestId, {required String reason});

  Future<void> cancelDeletion(String requestId, {required String reason});
}

class SupportActionsRepositoryImpl implements SupportActionsRepository {
  SupportActionsRepositoryImpl(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, String fallback) async {
    try {
      final res = await _dio.post(path, data: body);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw toAdminError(e, fallback);
    }
  }

  @override
  Future<OwnerPreview> preview(String tenantId, PreviewAction action, {String? reason, int? days}) async {
    final json = await _post(
        '/tenants/$tenantId/preview',
        {
          'action': action.api,
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
          if (days != null) 'days': days,
        },
        'No pudimos mostrar la vista previa.');
    return OwnerPreview(
      summary: (json['summary'] ?? '').toString(),
      reason: json['reason'] as String?,
      by: (json['by'] ?? 'Soporte Nexus').toString(),
    );
  }

  @override
  Future<RecoverySent> assistedRecovery(
    String tenantId, {
    required String reason,
    required Map<String, bool> checks,
    String? googleOrderId,
  }) async {
    final json = await _post(
        '/tenants/$tenantId/assisted-recovery',
        {
          'reason': reason.trim(),
          'checks': checks,
          if (googleOrderId != null && googleOrderId.trim().isNotEmpty) 'google_order_id': googleOrderId.trim(),
        },
        'No se envió el código.');
    return RecoverySent(
        sentTo: (json['sent_to'] ?? '').toString(), expiresAt: DateTime.parse(json['expires_at'] as String));
  }

  @override
  Future<TenantDetail> giftDays(String tenantId, {required int days, required String reason}) async =>
      TenantDetail.fromJson(await _post(
          '/tenants/$tenantId/gift-days', {'days': days, 'reason': reason.trim()}, 'No se regalaron los días.'));

  @override
  Future<TenantDetail> suspend(String tenantId, {required String reason}) async => TenantDetail.fromJson(
      await _post('/tenants/$tenantId/suspension', {'reason': reason.trim()}, 'No se suspendió la tienda.'));

  @override
  Future<TenantDetail> lift(String tenantId, {required String reason}) async => TenantDetail.fromJson(
      await _post('/tenants/$tenantId/suspension/lift', {'reason': reason.trim()}, 'No se levantó la suspensión.'));

  @override
  Future<String> export(String tenantId, {required String reason}) async {
    final json = await _post('/tenants/$tenantId/export', {'reason': reason.trim()}, 'No se pidió la exportación.');
    return (json['status'] ?? 'PENDING').toString();
  }

  @override
  Future<DeletionRequestRead> requestDeletion(String tenantId,
          {required String reason, required String confirmSlug}) async =>
      DeletionRequestRead.fromJson(await _post('/tenants/$tenantId/deletion',
          {'reason': reason.trim(), 'confirm_slug': confirmSlug.trim()}, 'No se pidió la eliminación.'));

  @override
  Future<void> approveDeletion(String requestId, {required String reason}) async =>
      _post('/approvals/$requestId/approve', {'reason': reason.trim()}, 'No se aprobó la eliminación.');

  @override
  Future<void> cancelDeletion(String requestId, {required String reason}) async =>
      _post('/approvals/$requestId/cancel', {'reason': reason.trim()}, 'No se canceló la eliminación.');
}

final supportActionsRepositoryProvider =
    Provider<SupportActionsRepository>((ref) => SupportActionsRepositoryImpl(ref.watch(adminDioProvider)));
