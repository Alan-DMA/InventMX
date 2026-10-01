"""Las acciones de la bitácora en palabras (feed, ficha y bitácora dicen lo mismo)."""
from typing import Optional

from app.modules.platform_admin.domain.audit_log import AuditAction, PlatformAuditLog

_ACTIONS = {
    AuditAction.ASSISTED_RECOVERY_SENT: "{op} envió un código de recuperación al dueño de {store}",
    AuditAction.ABUSE_SUSPENDED: "{op} suspendió {store} por abuso",
    AuditAction.ABUSE_LIFTED: "{op} levantó la suspensión de {store}",
    AuditAction.DATA_EXPORT_REQUESTED: "{op} pidió exportar los datos de {store}",
    AuditAction.DATA_EXPORT_SENT: "La exportación de {store} llegó al correo del dueño",
    AuditAction.TENANT_DELETION_REQUESTED: "{op} pidió eliminar {store}; falta la segunda aprobación",
    AuditAction.TENANT_DELETION_CANCELLED: "{op} canceló la eliminación de {store}",
    AuditAction.TENANT_DELETED: "{op} aprobó la eliminación: {store} ya no existe",
    AuditAction.SUPPORT_ACCESS_REVOKED: "El dueño de {store} retiró el acceso de soporte",
    AuditAction.SUPPORT_SESSION_STARTED: "{op} abrió una sesión de soporte en {store} (sólo lectura)",
    AuditAction.SUPPORT_SESSION_EXTENDED: "{op} siguió 30 min más en {store}",
    AuditAction.SUBSCRIPTION_SUSPENDED: "{store} quedó suspendida al terminar su gracia sin renovar",
    AuditAction.LOGIN_FAILED: "Acceso fallido al panel",
    AuditAction.TOTP_FAILED: "Código de autenticador incorrecto en el acceso de {op}",
    AuditAction.OPERATOR_LOCKED: "La cuenta de {op} se bloqueó por intentos fallidos",
    AuditAction.CASE_REPLIED: "{op} respondió un caso de {store}",
    AuditAction.CASE_STATUS_CHANGED: "{op} cambió el estado de un caso de {store}",
    AuditAction.HELP_TOPIC_UPDATED: "{op} editó un tema de ayuda",
    AuditAction.TENANT_VIEWED: "{op} abrió la ficha de {store}",
    AuditAction.LOGIN_SUCCEEDED: "{op} entró al panel",
    AuditAction.TOTP_ENROLLED: "{op} vinculó su autenticador",
    AuditAction.RECOVERY_CODE_USED: "{op} entró con un código de recuperación",
    AuditAction.OPERATOR_CREATED: "Alta de un operador del panel",
    AuditAction.OPERATOR_DEACTIVATED: "Baja de un operador del panel",
    AuditAction.TOTP_RESET: "Se reinició el autenticador de un operador",
    # Historial previo a P19
    AuditAction.PAYMENT_CONFIRMED: "{op} confirmó un pago manual de {store}",
    AuditAction.STATUS_CHANGED: "{op} cambió el estado de {store}",
    AuditAction.PLAN_CHANGED: "{op} cambió el plan de {store}",
    AuditAction.COURTESY_GRANTED: "{op} regaló un mes a {store}",
}


_SESSION_END = {
    "OPERATOR": "la terminó",
    "SIGNED_OUT": "terminó al salir del panel",
    "EXPIRED": "se acabó el tiempo",
    "GRANT_ENDED": "el dueño retiró el permiso",
    "NOT_OPENED": "el enlace venció sin abrirse",
    "OPERATOR_INACTIVE": "terminó por seguridad",
}


def operator_summary(entry: PlatformAuditLog, operator: Optional[str], store: Optional[str]) -> str:
    d = entry.details or {}
    op = operator or "Nexus"
    store = store or d.get("tienda") or "una tienda"
    if entry.action == AuditAction.DAYS_GIFTED:
        days = d.get("dias")
        return f"{op} regaló {days} {'día' if days == 1 else 'días'} a {store}"
    if entry.action == AuditAction.SUPPORT_SESSION_ENDED:
        how = _SESSION_END.get(d.get("fin"), "terminó")
        return f"Sesión de soporte de {op} en {store}: {how}"
    if entry.action == AuditAction.DATA_EXPORT_FAILED:
        return f"Falló la exportación de {store}: {d.get('error', 'sin detalle')}"
    if entry.action == AuditAction.SUPPORT_ACCESS_GRANTED:
        return f"El dueño de {store} concedió acceso de soporte por {d.get('horas', '?')} h"
    template = _ACTIONS.get(entry.action)
    return template.format(op=op, store=store) if template else entry.action
