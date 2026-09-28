"""
"Actividad de soporte" que ve el Dueño en Mi suscripción (P8, transparencia).

Sólo lo que soporte cambió en su suscripción, en palabras del tendero y con el
motivo tal cual lo escribimos. Las lecturas de la ficha (TENANT_VIEWED) y los
accesos al panel no se muestran aquí: no cambian nada de su cuenta.
"""
import uuid
from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.platform_admin.domain.audit_log import AuditAction, PlatformAuditLog
from app.modules.platform_admin.repositories.audit_repository import AuditRepository
from app.modules.platform_admin.repositories.operator_repository import OperatorRepository

_STATUS = {"ACTIVE": "activa", "SOFT_LOCK": "sólo lectura", "HARD_LOCK": "suspendida"}
_PLAN = {"EMPRENDEDOR": "Emprendedor", "COMERCIO": "Comercio", "CORPORATIVO": "Corporativo"}
_METHOD = {"CASH": "en efectivo", "MANUAL_SPEI": "por transferencia"}


class SupportActivityItem(BaseModel):
    occurred_at: datetime
    action: str
    summary: str
    reason: Optional[str] = None
    by: str


_MONTHS = ("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")


def _human_period(period: str) -> str:
    """'2026-09-28 a 2026-10-27' → '28 sep a 27 oct 2026' (como lo dice un tendero)."""
    try:
        start, end = (date.fromisoformat(p.strip()) for p in period.split(" a "))
    except (ValueError, AttributeError):
        return period
    first = f"{start.day} {_MONTHS[start.month - 1]}" + ("" if start.year == end.year else f" {start.year}")
    return f"{first} a {end.day} {_MONTHS[end.month - 1]} {end.year}"


def _reactivated(details: dict) -> str:
    return " Tu cuenta volvió a estar activa." if details.get("reactivado") else ""


def describe(entry: PlatformAuditLog) -> str:
    d = entry.details or {}
    if entry.action == AuditAction.PAYMENT_CONFIRMED:
        method = _METHOD.get(d.get("metodo"), "")
        return f"Confirmamos tu pago de ${d.get('monto_mxn', '')} {method}".strip() + "." + _reactivated(d)
    if entry.action == AuditAction.STATUS_CHANGED:
        return f"Tu cuenta pasó de {_STATUS.get(d.get('de'), d.get('de'))} a {_STATUS.get(d.get('a'), d.get('a'))}."
    if entry.action == AuditAction.PLAN_CHANGED:
        return f"Tu plan cambió de {_PLAN.get(d.get('de'), d.get('de'))} a {_PLAN.get(d.get('a'), d.get('a'))}."
    if entry.action == AuditAction.COURTESY_GRANTED:
        return f"Te dimos un mes sin costo ({_human_period(d.get('periodo', ''))})." + _reactivated(d)
    return "Soporte hizo un cambio en tu suscripción."


async def support_activity_for_tenant(db: AsyncSession, tenant_id: uuid.UUID, limit: int = 50) -> List[SupportActivityItem]:
    rows, _ = await AuditRepository(db).list(
        tenant_id=tenant_id, actions=AuditAction.TENANT_VISIBLE, limit=limit
    )
    names = await OperatorRepository(db).names_by_id(list({r.operator_id for r in rows if r.operator_id}))
    return [
        SupportActivityItem(
            occurred_at=r.occurred_at,
            action=r.action,
            summary=describe(r),
            reason=r.reason,
            by=f"Soporte Nexus · {names.get(r.operator_id, 'equipo')}",
        )
        for r in rows
    ]
