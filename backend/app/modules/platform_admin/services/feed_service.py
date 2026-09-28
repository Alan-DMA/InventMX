"""
"Feed del día" del Centro de soporte (brief confirmado, concept-seed `09cb4dce`).

- **Requiere atención**: sólo lo que pide decisión o seguimiento — eliminaciones
  esperando segunda aprobación, exportaciones en proceso o fallidas, accesos de
  soporte concedidos vigentes, códigos asistidos sin usar y suspensiones por
  abuso vigentes. Vacío = "Todo en orden".
- **Lo que pasó**: bitácora sin ruido (sin lecturas de fichas ni accesos
  exitosos) + tiendas nuevas, en un rango `[since, until)`. El cliente agrupa
  por día en su propia zona horaria: el servidor no decide dónde empieza un día.

Los textos van en la voz del operador ("Eduardo regaló 7 días a…"); los del
dueño están en `tenant_activity.py`.
"""
import uuid
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional

from sqlalchemy import select

from app.modules.platform_admin.domain.audit_log import AuditAction, PlatformAuditLog
from app.modules.platform_admin.domain.support import (
    ApprovalStatus,
    ExportStatus,
    PlatformApprovalRequest,
    PlatformExportJob,
)
from app.modules.platform_admin.schemas.platform_schemas import AttentionItem, Feed, FeedEvent
from app.modules.platform_admin.services.platform_admin_service import PlatformAdminService
from app.modules.platform_admin.services.support_service import EXPORT_STALE_AFTER

FEED_EVENT_LIMIT = 500
# Una exportación fallida deja de pedir atención tras una semana (o al reintentarla)
EXPORT_ATTENTION_WINDOW = timedelta(days=7)

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
    AuditAction.SUBSCRIPTION_SUSPENDED: "{store} quedó suspendida al terminar su gracia sin renovar",
    AuditAction.LOGIN_FAILED: "Acceso fallido al panel",
    AuditAction.TOTP_FAILED: "Código de autenticador incorrecto en el acceso de {op}",
    AuditAction.OPERATOR_LOCKED: "La cuenta de {op} se bloqueó por intentos fallidos",
    AuditAction.OPERATOR_CREATED: "Alta de un operador del panel",
    AuditAction.OPERATOR_DEACTIVATED: "Baja de un operador del panel",
    AuditAction.TOTP_RESET: "Se reinició el autenticador de un operador",
    # Historial previo a P19
    AuditAction.PAYMENT_CONFIRMED: "{op} confirmó un pago manual de {store}",
    AuditAction.STATUS_CHANGED: "{op} cambió el estado de {store}",
    AuditAction.PLAN_CHANGED: "{op} cambió el plan de {store}",
    AuditAction.COURTESY_GRANTED: "{op} regaló un mes a {store}",
}


def operator_summary(entry: PlatformAuditLog, operator: Optional[str], store: Optional[str]) -> str:
    d = entry.details or {}
    op = operator or "Nexus"
    store = store or d.get("tienda") or "una tienda"
    if entry.action == AuditAction.DAYS_GIFTED:
        days = d.get("dias")
        return f"{op} regaló {days} {'día' if days == 1 else 'días'} a {store}"
    if entry.action == AuditAction.DATA_EXPORT_FAILED:
        return f"Falló la exportación de {store}: {d.get('error', 'sin detalle')}"
    if entry.action == AuditAction.SUPPORT_ACCESS_GRANTED:
        return f"El dueño de {store} concedió acceso de soporte por {d.get('horas', '?')} h"
    template = _ACTIONS.get(entry.action)
    return template.format(op=op, store=store) if template else entry.action


class FeedService(PlatformAdminService):

    async def feed(self, since: Optional[datetime], until: Optional[datetime]) -> Feed:
        now = datetime.now(timezone.utc)
        until = until or now
        since = since or (until - timedelta(days=3))
        return Feed(
            attention=await self.attention(now),
            events=await self.events(since, until),
            since=since,
            until=until,
        )

    # ── Requiere atención ──────────────────────────────────────────────────

    async def attention(self, now: datetime) -> List[AttentionItem]:
        items: List[AttentionItem] = []

        deletions = (await self.db.execute(
            select(PlatformApprovalRequest)
            .where(PlatformApprovalRequest.status == ApprovalStatus.PENDING)
            .order_by(PlatformApprovalRequest.created_at.asc())
        )).scalars().all()
        names = await self.operators.names_by_id(list({d.requested_by for d in deletions}))
        for d in deletions:
            expired = d.expires_at <= now
            who = "Tú pediste" if d.requested_by == self.operator.id else f"{names.get(d.requested_by, 'Otro operador')} pidió"
            summary = f"{who} eliminarla; " + (
                "venció sin segunda aprobación" if expired
                else ("espera la aprobación del otro fundador" if d.requested_by == self.operator.id
                      else "te toca aprobarla o cancelarla")
            )
            items.append(AttentionItem(
                kind="DELETION_PENDING",
                tenant_id=d.tenant_id,
                tenant_name=d.tenant_name,
                since=d.created_at,
                until=d.expires_at,
                summary=summary,
                ref_id=str(d.id),
                awaiting_you=not expired and d.requested_by != self.operator.id,
            ))

        jobs = (await self.db.execute(
            select(PlatformExportJob)
            .where(PlatformExportJob.created_at > now - EXPORT_ATTENTION_WINDOW)
            .order_by(PlatformExportJob.created_at.desc())
        )).scalars().all()
        latest: Dict[uuid.UUID, PlatformExportJob] = {}
        for job in jobs:
            latest.setdefault(job.tenant_id, job)
        tenant_names = await self.reader.tenant_names(list(latest))
        for job in latest.values():
            if job.status == ExportStatus.PENDING:
                stale = job.created_at <= now - EXPORT_STALE_AFTER
                items.append(AttentionItem(
                    kind="EXPORT_FAILED" if stale else "EXPORT_IN_PROGRESS",
                    tenant_id=job.tenant_id,
                    tenant_name=tenant_names.get(job.tenant_id, "Tienda"),
                    since=job.created_at,
                    summary=(
                        "La exportación lleva más de 30 min sin terminar: el proceso se interrumpió; pídela de nuevo"
                        if stale else "Generando la exportación; llegará al correo del dueño"
                    ),
                    ref_id=str(job.id),
                ))
            elif job.status == ExportStatus.FAILED:
                items.append(AttentionItem(
                    kind="EXPORT_FAILED",
                    tenant_id=job.tenant_id,
                    tenant_name=tenant_names.get(job.tenant_id, "Tienda"),
                    since=job.finished_at or job.created_at,
                    summary=f"La exportación falló: {job.error or 'sin detalle'}",
                    ref_id=str(job.id),
                ))

        grants = await self.reader.active_grants(now)
        codes = await self.reader.unused_assisted_codes(now)
        suspended = await self.reader.abuse_suspended_tenants()
        more_names = await self.reader.tenant_names(list({g.tenant_id for g in grants} | {c.tenant_id for c in codes}))
        for grant in grants:
            items.append(AttentionItem(
                kind="SUPPORT_ACCESS_ACTIVE",
                tenant_id=grant.tenant_id,
                tenant_name=more_names.get(grant.tenant_id, "Tienda"),
                since=grant.created_at,
                until=grant.expires_at,
                summary="El dueño concedió acceso de soporte (sólo lectura)",
                ref_id=str(grant.id),
            ))
        for code in codes:
            items.append(AttentionItem(
                kind="ASSISTED_CODE_UNUSED",
                tenant_id=code.tenant_id,
                tenant_name=more_names.get(code.tenant_id, "Tienda"),
                since=code.created_at,
                until=code.expires_at,
                summary="Enviamos un código de recuperación y el dueño aún no lo usa",
            ))
        for tenant in suspended:
            rows, _ = await self.audit.list(tenant_id=tenant.id, actions=[AuditAction.ABUSE_SUSPENDED], limit=1)
            items.append(AttentionItem(
                kind="ABUSE_SUSPENSION",
                tenant_id=tenant.id,
                tenant_name=tenant.name,
                since=rows[0].occurred_at if rows else tenant.updated_at,
                summary=f"Suspendida por abuso: {rows[0].reason}" if rows and rows[0].reason else "Suspendida por abuso",
            ))

        # Lo que te toca a ti primero; luego lo más antiguo
        items.sort(key=lambda i: (not i.awaiting_you, i.since))
        return items

    # ── Lo que pasó ────────────────────────────────────────────────────────

    async def events(self, since: datetime, until: datetime) -> List[FeedEvent]:
        rows, _ = await self.audit.list(
            since=since, until=until, exclude_actions=AuditAction.FEED_NOISE, limit=FEED_EVENT_LIMIT,
        )
        operator_names = await self.operators.names_by_id(list({r.operator_id for r in rows if r.operator_id}))
        store_names = await self.reader.tenant_names(list({r.target_tenant_id for r in rows if r.target_tenant_id}))
        events = [
            FeedEvent(
                kind="AUDIT",
                occurred_at=r.occurred_at,
                action=r.action,
                tenant_id=r.target_tenant_id,
                tenant_name=store_names.get(r.target_tenant_id) or (r.details or {}).get("tienda"),
                operator_name=operator_names.get(r.operator_id),
                summary=operator_summary(
                    r, operator_names.get(r.operator_id), store_names.get(r.target_tenant_id),
                ),
                reason=r.reason,
            )
            for r in rows
        ]
        for tenant in await self.reader.signups_between(since, until):
            events.append(FeedEvent(
                kind="SIGNUP",
                occurred_at=tenant.created_at,
                tenant_id=tenant.id,
                tenant_name=tenant.name,
                summary=f"Se registró {tenant.name}",
            ))
        events.sort(key=lambda e: e.occurred_at, reverse=True)
        return events[:FEED_EVENT_LIMIT]
