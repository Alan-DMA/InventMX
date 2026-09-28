"""
Ciclo de la suscripción prepago (P9–P13, Sep 2026).

Suspende (HARD_LOCK) a los comercios cuya vigencia venció y ya pasaron sus días
de gracia. Sólo avanza, nunca desbloquea: lo que reactiva es un pago o una
regalo de días (`grant_period`). Una suspensión de soporte (HARD_LOCK por
abuso) tampoco se toca: el ciclo sólo mira comercios activos o en sólo lectura.

**Apagado** mientras `SUBSCRIPTION_ENFORCEMENT_ENABLED` sea falso: hoy nadie
tiene cómo renovar desde la app. Aun apagado, `run_subscription_cycle` calcula a
quién bloquearía (vista previa en el panel), para encenderlo sin sorpresas el
día que se integre Google Play.
"""
import asyncio
import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config.settings import settings
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantLockReason, TenantStatus
from app.modules.platform_admin.domain.audit_log import AuditAction
from app.modules.platform_admin.repositories.audit_repository import AuditRepository, RequestMeta
from app.modules.saas_billing.services.entitlement import (
    EntitlementState,
    entitlement_state,
    grace_until,
)

logger = logging.getLogger(__name__)
SYSTEM_META = RequestMeta(ip_address="sistema", user_agent="ciclo de suscripción")


@dataclass
class CycleTenant:
    tenant_id: str
    name: str
    paid_until: Optional[datetime]
    grace_until: Optional[datetime]


@dataclass
class CycleReport:
    enforced: bool
    checked: int = 0
    in_grace: List[CycleTenant] = field(default_factory=list)
    suspended: List[CycleTenant] = field(default_factory=list)


async def run_subscription_cycle(
    db: AsyncSession,
    now: Optional[datetime] = None,
    enforce: Optional[bool] = None,
) -> CycleReport:
    """
    Revisa los comercios activos o en sólo lectura. Con `enforce` (por omisión,
    la variable de configuración) suspende a los vencidos y lo anota en la
    bitácora como hecho por el sistema; sin él, sólo informa.
    """
    now = now or datetime.now(timezone.utc)
    enforce = settings.SUBSCRIPTION_ENFORCEMENT_ENABLED if enforce is None else enforce
    report = CycleReport(enforced=enforce)

    tenants = (await db.execute(
        select(Tenant).where(
            Tenant.status.in_([TenantStatus.ACTIVE, TenantStatus.SOFT_LOCK]),
            Tenant.paid_until.is_not(None),
            Tenant.paid_until <= now,
        )
    )).scalars().all()

    audit = AuditRepository(db)
    for tenant in tenants:
        report.checked += 1
        item = CycleTenant(str(tenant.id), tenant.name, tenant.paid_until, grace_until(tenant))
        state = entitlement_state(tenant, now)
        if state == EntitlementState.GRACIA:
            report.in_grace.append(item)
        elif state == EntitlementState.VENCIDA:
            report.suspended.append(item)
            if enforce:
                previous = tenant.status
                tenant.status = TenantStatus.HARD_LOCK
                tenant.lock_reason = TenantLockReason.NONPAYMENT.value
                await audit.append(
                    AuditAction.SUBSCRIPTION_SUSPENDED,
                    target_tenant_id=tenant.id,
                    target_type="tenant",
                    target_id=str(tenant.id),
                    reason="Terminó el periodo de gracia sin renovar la suscripción.",
                    details={
                        "de": previous.value,
                        "a": TenantStatus.HARD_LOCK.value,
                        "vencio": tenant.paid_until.isoformat(),
                        "gracia_hasta": item.grace_until.isoformat() if item.grace_until else None,
                    },
                    meta=SYSTEM_META,
                )
    if enforce and report.suspended:
        await db.commit()
    return report


async def subscription_cycle_loop() -> None:
    """Corre el ciclo cada `SUBSCRIPTION_CYCLE_INTERVAL_SECONDS`. Sólo se arranca si está encendido."""
    from app.core.database.session import AsyncSessionLocal

    while True:
        try:
            async with AsyncSessionLocal() as db:
                report = await run_subscription_cycle(db, enforce=True)
                if report.suspended:
                    logger.info("Ciclo de suscripción: %d comercios suspendidos.", len(report.suspended))
        except Exception:  # un error de una vuelta no debe matar el ciclo
            logger.exception("Falló una vuelta del ciclo de suscripción.")
        await asyncio.sleep(settings.SUBSCRIPTION_CYCLE_INTERVAL_SECONDS)
