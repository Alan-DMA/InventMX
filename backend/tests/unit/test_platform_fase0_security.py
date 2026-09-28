"""
Panel de plataforma — Fase 0: huecos de seguridad (Sep 2026).

1. Webhooks de pago firmados (HMAC-SHA256), idempotentes, con monto verificado y
   funcionales sin contexto de comercio (antes RLS les ocultaba la factura).
2. Un comercio no pide el respaldo global ni ve respaldos o cifras de otros.
3. El contexto RLS no sobrevive de una petición a otra en la conexión del pool.
"""
import json
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import pytest
from httpx import AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config.settings import settings
from app.core.database.session import AsyncSessionLocal, engine, get_db, set_tenant_context
from app.core.security.webhook_signature import sign_webhook_body
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan, TenantStatus
from app.modules.saas_billing.domain.subscription_invoice import (
    SaasPaymentMethod,
    SubscriptionInvoice,
    SubscriptionInvoiceStatus,
)

SECRET = "secreto-de-prueba"
SPEI = "/api/v1/webhooks/spei/payment-confirmation"
OXXO = "/api/v1/webhooks/oxxo/payment-confirmation"


async def _register(client: AsyncClient, prefix: str) -> tuple[dict, uuid.UUID]:
    suffix = uuid.uuid4().hex[:6]
    resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda {prefix} {suffix}",
            "slug": f"{prefix}-{suffix}",
            "full_name": "Doña Chuy",
            "email": f"{prefix}_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    return {"Authorization": f"Bearer {data['access_token']}"}, uuid.UUID(data["user"]["tenant_id"])


async def _locked_tenant_with_invoice(
    client: AsyncClient, db: AsyncSession, method: SaasPaymentMethod = SaasPaymentMethod.SPEI
) -> tuple[uuid.UUID, str]:
    """Comercio en SOFT_LOCK con una factura vencida de $399."""
    _, tenant_id = await _register(client, "webhook")
    await set_tenant_context(db, tenant_id)
    tenant = (await db.execute(select(Tenant).where(Tenant.id == tenant_id))).scalar_one()
    tenant.status = TenantStatus.SOFT_LOCK
    ref = f"NX{uuid.uuid4().hex[:12].upper()}"
    db.add(SubscriptionInvoice(
        tenant_id=tenant_id,
        plan=TenantPlan.COMERCIO,
        amount_mxn=Decimal("399.00"),
        payment_method=method,
        status=SubscriptionInvoiceStatus.OVERDUE,
        payment_reference=ref,
        oxxo_reference=ref if method == SaasPaymentMethod.OXXO else None,
        period_start=datetime.now(timezone.utc).date(),
        period_end=datetime.now(timezone.utc).date(),
    ))
    await db.commit()
    # El webhook llega sin sesión: la conexión queda sin comercio
    await set_tenant_context(db, None)
    return tenant_id, ref


def _spei_body(ref: str, amount: str = "399.00") -> bytes:
    return json.dumps({
        "reference_id": ref,
        "amount": amount,
        "payment_date": datetime.now(timezone.utc).isoformat(),
        "bank_confirmation": "STP-RAST-1234567890",
    }).encode("utf-8")


def _signed(body: bytes, secret: str = SECRET, prefix: str = "") -> dict:
    return {"Content-Type": "application/json", "X-Nexus-Signature": prefix + sign_webhook_body(body, secret)}


async def _state(db: AsyncSession, tenant_id: uuid.UUID, ref: str):
    await set_tenant_context(db, tenant_id)
    db.expire_all()
    invoice = (await db.execute(
        select(SubscriptionInvoice).where(SubscriptionInvoice.payment_reference == ref)
    )).scalar_one()
    tenant = (await db.execute(select(Tenant).where(Tenant.id == tenant_id))).scalar_one()
    return invoice.status, tenant.status


# -----------------------------------------------------------------------------
# 1. Webhooks
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_webhook_without_configured_secret_rejects_everything(client: AsyncClient, monkeypatch):
    """Falla cerrado: sin secreto en `.env` no se acepta ningún pago."""
    monkeypatch.setattr(settings, "SPEI_WEBHOOK_SECRET", "")
    body = _spei_body("NXCUALQUIERA")
    resp = await client.post(SPEI, content=body, headers=_signed(body, "lo-que-sea"))
    assert resp.status_code == 503


@pytest.mark.asyncio
async def test_unsigned_or_forged_webhook_does_not_pay(client: AsyncClient, db_session: AsyncSession, monkeypatch):
    """CA-P2: sin firma o con firma de otro secreto, la factura sigue vencida."""
    monkeypatch.setattr(settings, "SPEI_WEBHOOK_SECRET", SECRET)
    tenant_id, ref = await _locked_tenant_with_invoice(client, db_session)
    body = _spei_body(ref)

    unsigned = await client.post(SPEI, content=body, headers={"Content-Type": "application/json"})
    assert unsigned.status_code == 401
    forged = await client.post(SPEI, content=body, headers=_signed(body, "otro-secreto"))
    assert forged.status_code == 401
    # Firma válida de otro cuerpo: no sirve para este
    other = _spei_body(ref, amount="1.00")
    tampered = await client.post(SPEI, content=body, headers=_signed(other))
    assert tampered.status_code == 401

    assert await _state(db_session, tenant_id, ref) == (
        SubscriptionInvoiceStatus.OVERDUE, TenantStatus.SOFT_LOCK,
    )


@pytest.mark.asyncio
async def test_signed_webhook_pays_without_tenant_context_and_is_idempotent(
    client: AsyncClient, db_session: AsyncSession, monkeypatch
):
    """CA-P2: firmado paga y reactiva aunque la conexión no tenga comercio; repetido no reprocesa."""
    monkeypatch.setattr(settings, "SPEI_WEBHOOK_SECRET", SECRET)
    tenant_id, ref = await _locked_tenant_with_invoice(client, db_session)
    body = _spei_body(ref)

    first = await client.post(SPEI, content=body, headers=_signed(body))
    assert first.status_code == 200, first.text
    assert first.json()["status"] == "PAYMENT_CONFIRMED"
    assert first.json()["subscription_status"] == "ACTIVE"
    assert await _state(db_session, tenant_id, ref) == (
        SubscriptionInvoiceStatus.PAID, TenantStatus.ACTIVE,
    )

    await set_tenant_context(db_session, None)
    again = await client.post(SPEI, content=body, headers=_signed(body))
    assert again.status_code == 200
    assert again.json()["status"] == "ALREADY_PROCESSED"


@pytest.mark.asyncio
async def test_webhook_with_wrong_amount_is_left_for_review(
    client: AsyncClient, db_session: AsyncSession, monkeypatch
):
    """Un monto distinto al de la factura no la liquida ni desbloquea."""
    monkeypatch.setattr(settings, "SPEI_WEBHOOK_SECRET", SECRET)
    tenant_id, ref = await _locked_tenant_with_invoice(client, db_session)
    body = _spei_body(ref, amount="39.90")

    resp = await client.post(SPEI, content=body, headers=_signed(body))
    assert resp.status_code == 200
    assert resp.json()["status"] == "AMOUNT_MISMATCH"
    assert await _state(db_session, tenant_id, ref) == (
        SubscriptionInvoiceStatus.OVERDUE, TenantStatus.SOFT_LOCK,
    )


@pytest.mark.asyncio
async def test_oxxo_webhook_accepts_sha256_prefixed_signature(
    client: AsyncClient, db_session: AsyncSession, monkeypatch
):
    monkeypatch.setattr(settings, "OXXO_WEBHOOK_SECRET", SECRET)
    tenant_id, ref = await _locked_tenant_with_invoice(client, db_session, SaasPaymentMethod.OXXO)
    body = json.dumps({
        "reference_id": ref,
        "amount": "399.00",
        "payment_date": datetime.now(timezone.utc).isoformat(),
        "store_confirmation": "OXXO-TICKET-778",
    }).encode("utf-8")

    resp = await client.post(OXXO, content=body, headers=_signed(body, prefix="sha256="))
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "PAYMENT_CONFIRMED"


@pytest.mark.asyncio
async def test_signed_webhook_with_invalid_body_is_422(client: AsyncClient, monkeypatch):
    monkeypatch.setattr(settings, "SPEI_WEBHOOK_SECRET", SECRET)
    body = json.dumps({"reference_id": "NX1"}).encode("utf-8")
    resp = await client.post(SPEI, content=body, headers=_signed(body))
    assert resp.status_code == 422


# -----------------------------------------------------------------------------
# 2. /admin desde un comercio
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_store_owner_cannot_request_global_backup_nor_see_other_stores(client: AsyncClient):
    """CA-P1: el dueño de un comercio no es operador de la plataforma."""
    owner_a, _ = await _register(client, "backup-a")
    owner_b, _ = await _register(client, "backup-b")

    denied = await client.post(
        "/api/v1/admin/backups/create",
        json={"backup_type": "FULL", "include_all_tenants": True},
        headers=owner_a,
    )
    assert denied.status_code == 403

    mine = await client.post(
        "/api/v1/admin/backups/create",
        json={"backup_type": "FULL", "notes": "respaldo de A"},
        headers=owner_a,
    )
    assert mine.status_code == 201, mine.text
    backup_id = mine.json()["id"]

    listed_a = (await client.get("/api/v1/admin/backups/list", headers=owner_a)).json()
    assert backup_id in [b["id"] for b in listed_a["backups"]]
    listed_b = (await client.get("/api/v1/admin/backups/list", headers=owner_b)).json()
    assert backup_id not in [b["id"] for b in listed_b["backups"]]


@pytest.mark.asyncio
async def test_system_health_hides_platform_figures(client: AsyncClient):
    owner, _ = await _register(client, "health")
    diag = (await client.get("/api/v1/admin/system-health", headers=owner)).json()
    assert diag["active_tenants_count"] is None
    assert diag["total_products_count"] == 0
    assert diag["total_sales_count"] == 0


# -----------------------------------------------------------------------------
# 3. Contexto RLS entre peticiones
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_rls_context_does_not_leak_to_the_next_request():
    """
    La petición anterior deja fijado su comercio en la conexión; `get_db` debe
    limpiarlo antes de entregar la sesión a la siguiente.
    """
    leftover = str(uuid.uuid4())
    async with AsyncSessionLocal() as previous:
        await previous.execute(
            text("SELECT set_config('app.current_tenant', :t, false), set_config('app.bypass_rls', 'on', false)"),
            {"t": leftover},
        )
        await previous.commit()

    # Todas las conexiones del pool pasan por get_db: ninguna conserva el contexto
    sessions = []
    gens = []
    for _ in range(3):
        gen = get_db()
        session = await gen.__anext__()
        gens.append(gen)
        sessions.append(session)
        tenant = (await session.execute(text("SELECT current_setting('app.current_tenant', true)"))).scalar()
        bypass = (await session.execute(text("SELECT current_setting('app.bypass_rls', true)"))).scalar()
        assert tenant == ""
        assert bypass == "off"
    for gen in gens:
        await gen.aclose()
    # Este test usa el pool global de la app (no el del fixture): se libera para
    # que ninguna conexión quede atada a este event loop y rompa a otros tests.
    await engine.dispose()
