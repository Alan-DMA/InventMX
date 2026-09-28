"""
Vigencia prepago y ciclo de suscripción (P9–P13, Sep 2026).

El "enchufe" para Google Play: una sola fecha `paid_until` que alimentan el
registro, el panel y los webhooks por `grant_period`; el ciclo que suspende al
terminar la gracia existe y está probado, pero apagado por configuración.
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import engine
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantStatus
from app.modules.platform_admin.services.subscription_cycle import run_subscription_cycle
from app.modules.saas_billing.services.entitlement import (
    EntitlementState,
    SubscriptionSource,
    add_one_month,
    entitlement_state,
)
from test_platform_admin import P, _enrolled_session, _register_store

NOW = lambda: datetime.now(timezone.utc)  # noqa: E731


async def _tenant(db: AsyncSession, tenant_id: uuid.UUID) -> Tenant:
    db.expire_all()
    return (await db.execute(select(Tenant).where(Tenant.id == tenant_id))).scalar_one()


async def _set_paid_until(db: AsyncSession, tenant_id: uuid.UUID, days_ago: int, source: str = "TRIAL") -> None:
    tenant = await _tenant(db, tenant_id)
    tenant.paid_until = NOW() - timedelta(days=days_ago)
    tenant.subscription_source = source
    await db.commit()


def test_one_month_handles_short_months():
    assert add_one_month(datetime(2026, 1, 31, tzinfo=timezone.utc)).date().isoformat() == "2026-02-28"
    assert add_one_month(datetime(2028, 1, 31, tzinfo=timezone.utc)).date().isoformat() == "2028-02-29"
    assert add_one_month(datetime(2026, 12, 15, tzinfo=timezone.utc)).date().isoformat() == "2027-01-15"


@pytest.mark.asyncio
async def test_new_store_starts_with_one_month_and_no_renewal_in_app_yet(client: AsyncClient, db_session: AsyncSession):
    owner, tenant_id, _ = await _register_store(client, "vigencia")
    tenant = await _tenant(db_session, tenant_id)
    assert tenant.subscription_source == SubscriptionSource.TRIAL.value
    assert abs((tenant.paid_until - add_one_month(NOW())).total_seconds()) < 120

    sub = (await client.get("/api/v1/subscription", headers=owner)).json()
    assert sub["entitlement"] == "VIGENTE"
    assert sub["renewal_channel"] == "NONE"
    assert sub["current_period_end"][:10] == tenant.paid_until.date().isoformat()


@pytest.mark.asyncio
async def test_cycle_switched_off_only_reports(client: AsyncClient, db_session: AsyncSession):
    """CA-S2: apagado, nadie se bloquea solo; la vista previa dice a quién bloquearía."""
    _, tenant_id, _ = await _register_store(client, "apagado")
    await _set_paid_until(db_session, tenant_id, days_ago=30)

    report = await run_subscription_cycle(db_session)  # configuración por omisión: apagado
    assert report.enforced is False
    assert str(tenant_id) in [t.tenant_id for t in report.suspended]
    assert (await _tenant(db_session, tenant_id)).status == TenantStatus.ACTIVE


@pytest.mark.asyncio
async def test_cycle_on_keeps_grace_open_and_suspends_after_it(client: AsyncClient, db_session: AsyncSession):
    """P10: en gracia, acceso completo; al terminar, bloqueo total y queda en su actividad."""
    in_grace_owner, in_grace, _ = await _register_store(client, "engracia")
    expired_owner, expired, expired_email = await _register_store(client, "vencida")
    await _set_paid_until(db_session, in_grace, days_ago=5)
    await _set_paid_until(db_session, expired, days_ago=11)

    report = await run_subscription_cycle(db_session, enforce=True)
    assert str(in_grace) in [t.tenant_id for t in report.in_grace]
    assert str(expired) in [t.tenant_id for t in report.suspended]
    assert (await _tenant(db_session, in_grace)).status == TenantStatus.ACTIVE
    assert (await _tenant(db_session, expired)).status == TenantStatus.HARD_LOCK

    # Otra vuelta no vuelve a tocarlo ni duplica la bitácora
    again = await run_subscription_cycle(db_session, enforce=True)
    assert str(expired) not in [t.tenant_id for t in again.suspended]

    # El bloqueado sí entra (para renovar), ve su suscripción y nada más
    login = await client.post("/api/v1/auth/login", json={"email": expired_email, "password": "password123"})
    assert login.status_code == 200, login.text
    locked = {"Authorization": f"Bearer {login.json()['access_token']}"}
    sub = await client.get("/api/v1/subscription", headers=locked)
    assert sub.status_code == 200 and sub.json()["entitlement"] == "VENCIDA"
    assert (await client.get("/api/v1/users", headers=locked)).status_code == 402
    activity = (await client.get("/api/v1/subscription/activity", headers=locked)).json()
    assert activity[0]["action"] == "SUBSCRIPTION_SUSPENDED"
    assert activity[0]["by"] == "Nexus (automático)"
    assert "quedó suspendida hasta que renueves" in activity[0]["summary"]

    await engine.dispose()


@pytest.mark.asyncio
async def test_cycle_never_unlocks_nor_touches_a_manual_block(client: AsyncClient, db_session: AsyncSession):
    _, tenant_id, _ = await _register_store(client, "manual")
    tenant = await _tenant(db_session, tenant_id)
    tenant.status = TenantStatus.HARD_LOCK  # bloqueado a mano con vigencia por delante
    await db_session.commit()

    await run_subscription_cycle(db_session, enforce=True)
    assert (await _tenant(db_session, tenant_id)).status == TenantStatus.HARD_LOCK


@pytest.mark.asyncio
async def test_google_play_brings_its_own_grace(client: AsyncClient, db_session: AsyncSession):
    """Con Google Play la gracia la da Google: al pasar su vencimiento ya no hay días extra."""
    _, tenant_id, _ = await _register_store(client, "play")
    await _set_paid_until(db_session, tenant_id, days_ago=1, source=SubscriptionSource.GOOGLE_PLAY.value)
    assert entitlement_state(await _tenant(db_session, tenant_id)) == EntitlementState.VENCIDA


@pytest.mark.asyncio
async def test_gift_days_grant_periods(client: AsyncClient, db_session: AsyncSession):
    """
    Regalar días (P17) pasa por `grant_period`: suma sobre la vigencia (o desde
    hoy si venció), reactiva un bloqueo por falta de pago y, con Google Play,
    conserva la fuente (y su gracia) para posponer el cobro allá.
    """
    _, headers, _ = await _enrolled_session(client, db_session)
    reason = "Compensación por la caída del servicio del 20 de septiembre."

    _, current, _ = await _register_store(client, "regalo")
    before = (await _tenant(db_session, current)).paid_until
    gift = await client.post(f"{P}/tenants/{current}/gift-days", json={"days": 7, "reason": reason}, headers=headers)
    assert gift.status_code == 200, gift.text
    data = gift.json()
    assert data["subscription_source"] == "COURTESY"
    assert abs((datetime.fromisoformat(data["paid_until"]) - (before + timedelta(days=7))).total_seconds()) < 2

    _, locked, _ = await _register_store(client, "regalobloq")
    await _set_paid_until(db_session, locked, days_ago=20)
    tenant = await _tenant(db_session, locked)
    tenant.status, tenant.lock_reason = TenantStatus.HARD_LOCK, "NONPAYMENT"
    await db_session.commit()
    revived = (await client.post(f"{P}/tenants/{locked}/gift-days", json={"days": 3, "reason": reason}, headers=headers)).json()
    assert revived["status"] == "ACTIVE" and revived["lock_reason"] is None
    assert abs((datetime.fromisoformat(revived["paid_until"]) - (NOW() + timedelta(days=3))).total_seconds()) < 120

    _, play, _ = await _register_store(client, "regaloplay")
    await _set_paid_until(db_session, play, days_ago=-5, source=SubscriptionSource.GOOGLE_PLAY.value)
    kept = (await client.post(f"{P}/tenants/{play}/gift-days", json={"days": 10, "reason": reason}, headers=headers)).json()
    assert kept["subscription_source"] == "GOOGLE_PLAY"


@pytest.mark.asyncio
async def test_cycle_preview_endpoint(client: AsyncClient, db_session: AsyncSession):
    _, headers, _ = await _enrolled_session(client, db_session)
    _, tenant_id, _ = await _register_store(client, "preview")
    await _set_paid_until(db_session, tenant_id, days_ago=20)

    preview = (await client.get(f"{P}/subscription-cycle/preview", headers=headers)).json()
    assert preview["enforcement_enabled"] is False
    assert str(tenant_id) in [t["tenant_id"] for t in preview["would_suspend"]]
    assert (await _tenant(db_session, tenant_id)).status == TenantStatus.ACTIVE
