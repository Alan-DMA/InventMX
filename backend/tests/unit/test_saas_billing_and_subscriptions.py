# Importación de precisión decimal
from decimal import Decimal
# Importación de fecha y hora
from datetime import datetime, timezone
import uuid

# Importación de pytest y httpx
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de modelos y utilidades de prueba
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan, TenantStatus
from app.modules.saas_billing.domain.subscription_invoice import (
    SaasPaymentMethod,
    SubscriptionInvoice,
    SubscriptionInvoiceStatus,
)


async def create_store_and_get_auth(client: AsyncClient):
    """Registra una tienda y usuario y retorna (headers, tenant_id, user_id)."""
    suffix = uuid.uuid4().hex[:6]
    resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda SaaS {suffix}",
            "slug": f"saas-store-{suffix}",
            "full_name": f"Owner SaaS {suffix}",
            "email": f"saas_{suffix}@nexus.mx",
            "password": "Password123!",
        },
    )
    assert resp.status_code == 201
    data = resp.json()
    token = data["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return headers, data["user"]["tenant_id"], data["user"]["id"]


@pytest.mark.asyncio
async def test_get_saas_plans_catalog(client: AsyncClient):
    """
    Verifica que el catálogo público de planes SaaS retorne los tres niveles canónicos
    con sus precios en Pesos Mexicanos (EMPRENDEDOR $199, COMERCIO $399, CORPORATIVO $699).
    """
    response = await client.get("/api/v1/saas/plans")
    assert response.status_code == 200
    plans = response.json()
    assert len(plans) == 3

    plan_map = {p["id"]: p for p in plans}
    assert "EMPRENDEDOR" in plan_map
    assert "COMERCIO" in plan_map
    assert "CORPORATIVO" in plan_map

    assert float(plan_map["EMPRENDEDOR"]["monthly_price_mxn"]) == 199.00
    assert float(plan_map["COMERCIO"]["monthly_price_mxn"]) == 399.00
    assert float(plan_map["CORPORATIVO"]["monthly_price_mxn"]) == 699.00


@pytest.mark.asyncio
async def test_get_current_subscription_info(client: AsyncClient):
    """
    Verifica que un comercio autenticado pueda consultar su estado de suscripción y límites.
    """
    headers, tenant_id, _ = await create_store_and_get_auth(client)
    response = await client.get(
        "/api/v1/subscription",
        headers=headers,
    )
    assert response.status_code == 200
    data = response.json()
    assert "id" in data
    assert "plan" in data
    assert "status" in data
    assert "usage_stats" in data
    assert data["status"] == "ACTIVE"


@pytest.mark.asyncio
async def test_change_plan_success(client: AsyncClient):
    """
    Verifica que un comercio pueda solicitar cambio a un plan superior (Upgrade a CORPORATIVO).
    """
    headers, _, _ = await create_store_and_get_auth(client)
    payload = {
        "new_plan": "CORPORATIVO",
        "change_immediately": True,
        "reason": "Expansión a nueva sucursal",
    }
    response = await client.post(
        "/api/v1/subscription/change-plan",
        json=payload,
        headers=headers,
    )
    assert response.status_code == 200
    data = response.json()
    assert data["subscription"]["plan"] == "CORPORATIVO"
    assert data["plan_change"]["to_plan"] == "CORPORATIVO"


@pytest.mark.asyncio
async def test_generate_payment_methods_spei_and_oxxo(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Verifica la generación de CLABE interbancaria de 18 dígitos para SPEI
    y referencia numérica de 14 dígitos para pago en OXXO Pay.
    """
    from app.core.database.session import set_tenant_context
    headers, tenant_id_str, _ = await create_store_and_get_auth(client)
    tenant_id = uuid.UUID(tenant_id_str)
    await set_tenant_context(db_session, tenant_id)

    # 1. Crear una factura de prueba en la base de datos
    invoice = SubscriptionInvoice(
        tenant_id=tenant_id,
        plan=TenantPlan.COMERCIO,
        amount_mxn=Decimal("399.00"),
        payment_method=SaasPaymentMethod.SPEI,
        status=SubscriptionInvoiceStatus.PENDING,
        period_start=datetime.now(timezone.utc).date(),
        period_end=datetime.now(timezone.utc).date(),
    )
    db_session.add(invoice)
    await db_session.commit()
    await set_tenant_context(db_session, tenant_id)

    # 2. Solicitar instrucciones de pago por SPEI
    spei_resp = await client.post(
        f"/api/v1/billing/invoices/{invoice.id}/payment-methods",
        json={"payment_method": "SPEI"},
        headers=headers,
    )
    assert spei_resp.status_code == 200
    spei_data = spei_resp.json()
    assert spei_data["payment_method"] == "SPEI"
    assert len(spei_data["clabe"]) == 18
    assert spei_data["clabe"].startswith("646180")
    assert spei_data["bank_name"] == "STP"

    # 3. Solicitar instrucciones de pago por OXXO
    oxxo_resp = await client.post(
        f"/api/v1/billing/invoices/{invoice.id}/payment-methods",
        json={"payment_method": "OXXO"},
        headers=headers,
    )
    assert oxxo_resp.status_code == 200
    oxxo_data = oxxo_resp.json()
    assert oxxo_data["payment_method"] == "OXXO"
    assert "barcode" in oxxo_data
    assert "reference_number" in oxxo_data


@pytest.mark.asyncio
async def test_spei_webhook_reconciliation_and_account_reactivation(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Verifica que la recepción de un webhook de pago SPEI STP liquide la factura
    y reactive la cuenta si el comercio se encontraba en SOFT_LOCK.
    """
    from app.core.database.session import set_tenant_context
    headers, tenant_id_str, _ = await create_store_and_get_auth(client)
    tenant_id = uuid.UUID(tenant_id_str)
    await set_tenant_context(db_session, tenant_id)

    # 1. Simular comercio en estado de morosidad SOFT_LOCK
    from sqlalchemy import select
    res = await db_session.execute(select(Tenant).where(Tenant.id == tenant_id))
    t = res.scalar_one()
    t.status = TenantStatus.SOFT_LOCK

    ref = f"NX202609TEST{uuid.uuid4().hex[:6]}"
    invoice = SubscriptionInvoice(
        tenant_id=tenant_id,
        plan=TenantPlan.COMERCIO,
        amount_mxn=Decimal("399.00"),
        payment_method=SaasPaymentMethod.SPEI,
        status=SubscriptionInvoiceStatus.OVERDUE,
        payment_reference=ref,
        period_start=datetime.now(timezone.utc).date(),
        period_end=datetime.now(timezone.utc).date(),
    )
    db_session.add(invoice)
    await db_session.commit()
    await set_tenant_context(db_session, tenant_id)

    # 2. Disparar el webhook de confirmación bancaria
    webhook_payload = {
        "reference_id": ref,
        "amount": 399.00,
        "payment_date": datetime.now(timezone.utc).isoformat(),
        "bank_confirmation": "STP-RAST-1234567890",
        "sender_account": "1234",
        "sender_bank": "BBVA",
    }
    response = await client.post(
        "/api/v1/webhooks/spei/payment-confirmation",
        json=webhook_payload,
    )
    assert response.status_code == 200
    res_data = response.json()
    assert res_data["status"] == "PAYMENT_CONFIRMED"
    assert res_data["subscription_status"] == "ACTIVE"

    # 3. Comprobar que la factura esté en estado PAID
    await set_tenant_context(db_session, tenant_id)
    await db_session.refresh(invoice)
    assert invoice.status == SubscriptionInvoiceStatus.PAID
    assert invoice.paid_at is not None

    # 4. Comprobar que el tenant quedó reactivado en ACTIVE
    await db_session.refresh(t)
    assert t.status == TenantStatus.ACTIVE
