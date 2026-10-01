/// Un renglón de la bitácora de la plataforma, ya en palabras.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.occurredAt,
    required this.action,
    required this.summary,
    this.operatorName,
    this.targetTenantId,
    this.reason,
    this.ipAddress,
  });

  final int id;
  final DateTime occurredAt;
  final String action;
  final String summary;
  final String? operatorName;
  final String? targetTenantId;
  final String? reason;
  final String? ipAddress;

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: (json['id'] as num).toInt(),
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        action: (json['action'] ?? '').toString(),
        summary: (json['summary'] ?? json['action'] ?? '').toString(),
        operatorName: json['operator_name'] as String?,
        targetTenantId: json['target_tenant_id']?.toString(),
        reason: json['reason'] as String?,
        ipAddress: json['ip_address'] as String?,
      );
}

class AuditPage {
  const AuditPage({required this.items, required this.total});
  final List<AuditEntry> items;
  final int total;
}

/// Resultado de recalcular la cadena de hashes.
class ChainVerification {
  const ChainVerification({required this.intact, required this.checked, this.brokenAtId});
  final bool intact;
  final int checked;
  final int? brokenAtId;
}

/// Los tipos de acción, en palabras y agrupados (filtro de la bitácora).
class AuditActionGroup {
  const AuditActionGroup(this.title, this.actions);
  final String title;
  final List<(String code, String label)> actions;
}

const auditActionGroups = [
  AuditActionGroup('Acciones sobre tiendas', [
    ('DAYS_GIFTED', 'Regaló días'),
    ('ABUSE_SUSPENDED', 'Suspendió por abuso'),
    ('ABUSE_LIFTED', 'Levantó una suspensión'),
    ('ASSISTED_RECOVERY_SENT', 'Envió un código de acceso'),
    ('DATA_EXPORT_REQUESTED', 'Pidió una exportación'),
    ('DATA_EXPORT_SENT', 'Exportación enviada'),
    ('DATA_EXPORT_FAILED', 'Exportación fallida'),
    ('SUPPORT_ACCESS_GRANTED', 'El dueño concedió acceso'),
    ('SUPPORT_ACCESS_REVOKED', 'El dueño retiró el acceso'),
    ('TENANT_VIEWED', 'Abrió una ficha'),
  ]),
  AuditActionGroup('Eliminaciones', [
    ('TENANT_DELETION_REQUESTED', 'Pidió eliminar una tienda'),
    ('TENANT_DELETION_CANCELLED', 'Canceló una eliminación'),
    ('TENANT_DELETED', 'Eliminó una tienda'),
  ]),
  AuditActionGroup('Casos', [
    ('CASE_REPLIED', 'Respondió un caso'),
    ('CASE_STATUS_CHANGED', 'Cambió el estado de un caso'),
  ]),
  AuditActionGroup('Temas de ayuda', [
    ('HELP_TOPIC_UPDATED', 'Editó un tema de ayuda'),
  ]),
  AuditActionGroup('Accesos al panel', [
    ('LOGIN_SUCCEEDED', 'Entró al panel'),
    ('LOGIN_FAILED', 'Acceso fallido'),
    ('TOTP_FAILED', 'Código de autenticador incorrecto'),
    ('TOTP_ENROLLED', 'Vinculó su autenticador'),
    ('RECOVERY_CODE_USED', 'Usó un código de recuperación'),
    ('OPERATOR_LOCKED', 'Cuenta bloqueada por intentos'),
  ]),
];

String? auditActionLabel(String code) {
  for (final g in auditActionGroups) {
    for (final (c, label) in g.actions) {
      if (c == code) return label;
    }
  }
  return null;
}

/// Accesos al panel: ahí la IP ayuda a reconocer un intento ajeno.
const accessActions = {'LOGIN_SUCCEEDED', 'LOGIN_FAILED', 'TOTP_FAILED', 'RECOVERY_CODE_USED', 'OPERATOR_LOCKED'};
