"""
Vigencia de la suscripción (modelo prepago de Eduardo, P9–P13 — Sep 2026).

Una sola fuente de verdad: `tenants.paid_until`. Todo lo que otorga un periodo
pasa por `grant_period` —la prueba del registro, la cortesía y el pago manual
del panel, los webhooks de pasarela y, el día que se integre, Google Play—, así
que conectar Google sólo es llamar a esta función con la fecha de vencimiento
que dé su API.

Estados de la vigencia:
- VIGENTE: `now < paid_until`.
- GRACIA: venció, pero dentro de los días de gracia. **Acceso completo** (P10,
  como lo exige Google Play durante su periodo de gracia).
- VENCIDA: terminó la gracia → el ciclo la bloquea (HARD_LOCK), si está
  encendido (`SUBSCRIPTION_ENFORCEMENT_ENABLED`).

Con Google Play la gracia la maneja Google (extiende su vencimiento mientras
reintenta el cobro), por eso su fuente no suma días propios de gracia.
"""
import calendar
import enum
from datetime import datetime, timedelta, timezone
from typing import Optional

from app.core.config.settings import settings
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantLockReason, TenantStatus


class SubscriptionSource(str, enum.Enum):
    TRIAL = "TRIAL"              # Primer mes desde el registro
    COURTESY = "COURTESY"        # Mes de cortesía desde el panel
    MANUAL = "MANUAL"            # Pago confirmado a mano en el panel
    GATEWAY = "GATEWAY"          # Webhook de pasarela (SPEI/OXXO), a futuro
    GOOGLE_PLAY = "GOOGLE_PLAY"  # Google Play Billing (P13), por integrar


class EntitlementState(str, enum.Enum):
    VIGENTE = "VIGENTE"
    GRACIA = "GRACIA"
    VENCIDA = "VENCIDA"
    SIN_FECHA = "SIN_FECHA"      # Comercio anterior al modelo (no debería quedar ninguno)


def add_one_month(moment: datetime) -> datetime:
    """Mismo día del mes siguiente, o el último si no existe (31 ene → 28/29 feb)."""
    year = moment.year + (moment.month // 12)
    month = moment.month % 12 + 1
    day = min(moment.day, calendar.monthrange(year, month)[1])
    return moment.replace(year=year, month=month, day=day)


def grace_days(source: Optional[str]) -> int:
    if source == SubscriptionSource.GOOGLE_PLAY.value:
        return 0
    return settings.SUBSCRIPTION_GRACE_DAYS


def grace_until(tenant: Tenant) -> Optional[datetime]:
    if tenant.paid_until is None:
        return None
    return tenant.paid_until + timedelta(days=grace_days(tenant.subscription_source))


def entitlement_state(tenant: Tenant, now: Optional[datetime] = None) -> EntitlementState:
    now = now or datetime.now(timezone.utc)
    if tenant.paid_until is None:
        return EntitlementState.SIN_FECHA
    if now < tenant.paid_until:
        return EntitlementState.VIGENTE
    if now < grace_until(tenant):
        return EntitlementState.GRACIA
    return EntitlementState.VENCIDA


def period_from_payment(paid_at: datetime) -> datetime:
    """P12: el mes nuevo siempre cuenta desde el día en que paga."""
    return add_one_month(paid_at)


def one_more_month(tenant: Tenant, now: Optional[datetime] = None) -> datetime:
    """Cortesía: un mes más sobre lo que ya tenga pagado (o desde hoy si ya venció)."""
    now = now or datetime.now(timezone.utc)
    base = tenant.paid_until if tenant.paid_until and tenant.paid_until > now else now
    return add_one_month(base)


def grant_period(tenant: Tenant, until: datetime, source: SubscriptionSource) -> bool:
    """
    Otorga vigencia hasta `until` y reactiva si estaba bloqueado. Devuelve si
    lo reactivó. Quien llama se encarga de la bitácora y del commit.

    Una suspensión de soporte por abuso (P17) **no** se levanta pagando ni con
    días de regalo: sólo soporte la quita, a propósito y con motivo.
    """
    tenant.paid_until = until
    tenant.subscription_source = source.value
    if tenant.lock_reason == TenantLockReason.ABUSE.value:
        return False
    if tenant.status != TenantStatus.ACTIVE:
        tenant.status = TenantStatus.ACTIVE
        tenant.lock_reason = None
        return True
    return False
