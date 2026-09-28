"""
Panel de plataforma — Fase 1 (Sep 2026): acceso con TOTP, separación de tokens,
comercios sólo con metadatos, acciones de suscripción con motivo, bitácora
inalterable y transparencia hacia el Dueño. Un test por criterio (CA-P3…CA-P8).
"""
import base64
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import pytest
from httpx import AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import engine, set_tenant_context
from app.core.security.password import get_password_hash
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantStatus
from app.modules.platform_admin.domain.operator import PlatformOperator
from app.modules.platform_admin.security import totp
from app.modules.saas_billing.domain.subscription_invoice import (
    SaasPaymentMethod,
    SubscriptionInvoice,
    SubscriptionInvoiceStatus,
)

P = "/api/v1/platform"
PASSWORD = "ClaveDeFundador2026"


# -----------------------------------------------------------------------------
# Ayudantes
# -----------------------------------------------------------------------------

class Operator:
    """Operador de prueba con su secreto TOTP y el último paso usado."""

    def __init__(self, email: str):
        self.email = email
        self.secret = None
        self.step = None

    def next_code(self) -> str:
        # Un código no se acepta dos veces: se usa el siguiente paso de la ventana
        step = totp.current_step() if self.step is None else self.step + 1
        self.step = step
        return totp.code_at(self.secret, step)


async def _new_operator(db: AsyncSession) -> Operator:
    email = f"op_{uuid.uuid4().hex[:8]}@nexus.mx"
    db.add(PlatformOperator(email=email, full_name="Operadora de Prueba", hashed_password=get_password_hash(PASSWORD)))
    await db.commit()
    return Operator(email)


async def _enrolled_session(client: AsyncClient, db: AsyncSession) -> tuple[Operator, dict, dict]:
    """Primer acceso completo: contraseña → QR → primer código. Devuelve headers y la sesión."""
    op = await _new_operator(db)
    login = await client.post(f"{P}/auth/login", json={"email": op.email, "password": PASSWORD})
    assert login.status_code == 200, login.text
    body = login.json()
    assert body["status"] == "ENROLLMENT_REQUIRED"
    op.secret = body["manual_secret"]
    session = await client.post(
        f"{P}/auth/verify", json={"challenge_token": body["challenge_token"], "code": op.next_code()}
    )
    assert session.status_code == 200, session.text
    data = session.json()
    return op, {"Authorization": f"Bearer {data['access_token']}"}, data


async def _register_store(client: AsyncClient, prefix: str = "panel") -> tuple[dict, uuid.UUID, str]:
    suffix = uuid.uuid4().hex[:6]
    email = f"{prefix}_{suffix}@tienda.mx"
    resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes {prefix} {suffix}",
            "slug": f"{prefix}-{suffix}",
            "full_name": "Doña Chuy",
            "email": email,
            "password": "password123",
        },
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    return {"Authorization": f"Bearer {data['access_token']}"}, uuid.UUID(data["user"]["tenant_id"]), email


async def _overdue_invoice(db: AsyncSession, tenant_id: uuid.UUID, lock: TenantStatus) -> uuid.UUID:
    await set_tenant_context(db, tenant_id)
    tenant = (await db.execute(select(Tenant).where(Tenant.id == tenant_id))).scalar_one()
    tenant.status = lock
    invoice = SubscriptionInvoice(
        tenant_id=tenant_id,
        plan=tenant.plan_id,
        amount_mxn=Decimal("199.00"),
        payment_method=SaasPaymentMethod.SPEI,
        status=SubscriptionInvoiceStatus.OVERDUE,
        payment_reference=f"NX{uuid.uuid4().hex[:10].upper()}",
        period_start=datetime.now(timezone.utc).date() - timedelta(days=40),
        period_end=datetime.now(timezone.utc).date() - timedelta(days=10),
    )
    db.add(invoice)
    await db.commit()
    await set_tenant_context(db, None)
    return invoice.id


# -----------------------------------------------------------------------------
# TOTP (RFC 6238)
# -----------------------------------------------------------------------------

def test_totp_matches_rfc6238_vectors():
    """Vectores SHA-1 del RFC 6238 (últimos 6 dígitos de los de 8)."""
    secret = base64.b32encode(b"12345678901234567890").decode().rstrip("=")
    assert totp.code_at(secret, 59 // 30) == "287082"
    assert totp.code_at(secret, 1111111109 // 30) == "081804"
    assert totp.code_at(secret, 1234567890 // 30) == "005924"


def test_totp_window_and_no_reuse():
    secret = totp.generate_secret()
    now = 1_900_000_000.0
    step = totp.current_step(now)
    assert totp.verify(secret, totp.code_at(secret, step - 1), None, now) == step - 1
    assert totp.verify(secret, totp.code_at(secret, step + 2), None, now) is None
    # Ya usado ese paso: el mismo código no vuelve a entrar
    assert totp.verify(secret, totp.code_at(secret, step), step, now) is None
    assert totp.verify(secret, "12345", None, now) is None


# -----------------------------------------------------------------------------
# Acceso (CA-P3)
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_first_access_enrolls_totp_and_hands_recovery_codes_once(client: AsyncClient, db_session: AsyncSession):
    op, headers, session = await _enrolled_session(client, db_session)
    assert len(session["recovery_codes"]) == 10
    assert session["recovery_codes_remaining"] == 10
    assert session["expires_in"] == 120 * 60

    me = await client.get(f"{P}/auth/me", headers=headers)
    assert me.status_code == 200 and me.json()["email"] == op.email

    # El siguiente acceso ya pide código y no vuelve a entregar códigos de recuperación
    login = (await client.post(f"{P}/auth/login", json={"email": op.email, "password": PASSWORD})).json()
    assert login["status"] == "TOTP_REQUIRED"
    assert login["otpauth_uri"] is None
    again = await client.post(f"{P}/auth/verify", json={"challenge_token": login["challenge_token"], "code": op.next_code()})
    assert again.status_code == 200
    assert again.json()["recovery_codes"] is None


@pytest.mark.asyncio
async def test_password_alone_never_opens_the_panel(client: AsyncClient, db_session: AsyncSession):
    """El reto no sirve como sesión; sin código no hay acceso."""
    op = await _new_operator(db_session)
    login = (await client.post(f"{P}/auth/login", json={"email": op.email, "password": PASSWORD})).json()
    as_access = await client.get(f"{P}/metrics", headers={"Authorization": f"Bearer {login['challenge_token']}"})
    assert as_access.status_code == 401


@pytest.mark.asyncio
async def test_a_used_code_cannot_be_replayed(client: AsyncClient, db_session: AsyncSession):
    op, _, _ = await _enrolled_session(client, db_session)
    used = totp.code_at(op.secret, op.step)
    login = (await client.post(f"{P}/auth/login", json={"email": op.email, "password": PASSWORD})).json()
    replay = await client.post(f"{P}/auth/verify", json={"challenge_token": login["challenge_token"], "code": used})
    assert replay.status_code == 401


@pytest.mark.asyncio
async def test_five_failures_lock_the_account_for_fifteen_minutes(client: AsyncClient, db_session: AsyncSession):
    """CA-P3: el 6.º intento —aun con la contraseña correcta— encuentra la cuenta bloqueada."""
    op = await _new_operator(db_session)
    for _ in range(5):
        bad = await client.post(f"{P}/auth/login", json={"email": op.email, "password": "equivocada"})
        assert bad.status_code == 401
    sixth = await client.post(f"{P}/auth/login", json={"email": op.email, "password": PASSWORD})
    assert sixth.status_code == 423
    assert "bloqueada" in sixth.json()["detail"]


@pytest.mark.asyncio
async def test_unknown_email_gets_the_same_answer(client: AsyncClient):
    resp = await client.post(f"{P}/auth/login", json={"email": "nadie@nexus.mx", "password": PASSWORD})
    assert resp.status_code == 401
    assert resp.json()["detail"] == "Correo, contraseña o código incorrectos."


@pytest.mark.asyncio
async def test_recovery_code_works_once(client: AsyncClient, db_session: AsyncSession):
    op, _, session = await _enrolled_session(client, db_session)
    code = session["recovery_codes"][0]

    login = (await client.post(f"{P}/auth/login", json={"email": op.email, "password": PASSWORD})).json()
    ok = await client.post(f"{P}/auth/recover", json={"challenge_token": login["challenge_token"], "recovery_code": code})
    assert ok.status_code == 200, ok.text
    assert ok.json()["recovery_codes_remaining"] == 9

    login = (await client.post(f"{P}/auth/login", json={"email": op.email, "password": PASSWORD})).json()
    reused = await client.post(f"{P}/auth/recover", json={"challenge_token": login["challenge_token"], "recovery_code": code})
    assert reused.status_code == 401


# -----------------------------------------------------------------------------
# Separación de tokens (CA-P4)
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_store_and_platform_tokens_do_not_cross(client: AsyncClient, db_session: AsyncSession):
    store_headers, _, _ = await _register_store(client, "cruce")
    _, platform_headers, _ = await _enrolled_session(client, db_session)

    assert (await client.get(f"{P}/tenants", headers=store_headers)).status_code == 401
    assert (await client.get(f"{P}/metrics", headers=store_headers)).status_code == 401
    assert (await client.get("/api/v1/auth/me", headers=platform_headers)).status_code == 401
    assert (await client.get("/api/v1/inventory/products", headers=platform_headers)).status_code == 401


# -----------------------------------------------------------------------------
# Comercios: sólo metadatos (CA-P5)
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_directory_shows_metadata_only(client: AsyncClient, db_session: AsyncSession):
    _, headers, _ = await _enrolled_session(client, db_session)
    store_headers, tenant_id, owner_email = await _register_store(client, "directorio")
    await client.post(
        "/api/v1/inventory/products", json={"name": "Coca-Cola 600ml", "price_mxn": "18.00"}, headers=store_headers,
    )

    page = (await client.get(f"{P}/tenants", params={"q": owner_email}, headers=headers)).json()
    assert page["total"] == 1
    item = page["items"][0]
    assert item["id"] == str(tenant_id)
    assert item["owner_email"] == owner_email
    assert item["users_count"] == 1
    assert item["last_activity_at"] is None  # se registró pero no ha iniciado sesión por login
    assert set(item) == {
        "id", "name", "slug", "plan", "status", "created_at", "owner_name", "owner_email",
        "users_count", "users_limit", "last_activity_at", "open_invoices",
    }

    detail = await client.get(f"{P}/tenants/{tenant_id}", headers=headers)
    assert detail.status_code == 200
    body = detail.text.lower()
    assert "coca-cola" not in body and "price" not in body


# -----------------------------------------------------------------------------
# Suscripciones con motivo, reactivación inmediata y transparencia (CA-P6…P8)
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_confirming_a_payment_reactivates_immediately_and_owner_sees_why(
    client: AsyncClient, db_session: AsyncSession
):
    op, headers, _ = await _enrolled_session(client, db_session)
    _, tenant_id, owner_email = await _register_store(client, "pago")
    invoice_id = await _overdue_invoice(db_session, tenant_id, TenantStatus.SOFT_LOCK)

    # El Dueño entra estando en sólo lectura: su token lleva SOFT_LOCK
    login = await client.post("/api/v1/auth/login", json={"email": owner_email, "password": "password123"})
    owner = {"Authorization": f"Bearer {login.json()['access_token']}"}
    blocked = await client.post("/api/v1/inventory/categories", json={"name": "Dulces"}, headers=owner)
    assert blocked.status_code == 403

    short = await client.post(
        f"{P}/tenants/{tenant_id}/payments/confirm",
        json={"invoice_id": str(invoice_id), "method": "CASH", "reason": "pagó"},
        headers=headers,
    )
    assert short.status_code == 422

    reason = "Pagó en efectivo en la visita del 27 de septiembre."
    confirmed = await client.post(
        f"{P}/tenants/{tenant_id}/payments/confirm",
        json={"invoice_id": str(invoice_id), "method": "CASH", "reference": "REC-001", "reason": reason},
        headers=headers,
    )
    assert confirmed.status_code == 200, confirmed.text
    detail = confirmed.json()
    assert detail["status"] == "ACTIVE"
    assert detail["invoices"][0]["status"] == "PAID"
    assert detail["activity"][0]["action"] == "PAYMENT_CONFIRMED"
    assert detail["activity"][0]["reason"] == reason
    assert detail["activity"][0]["operator_name"] == "Operadora de Prueba"

    # CA-P7: el mismo token (aún dice SOFT_LOCK) ya puede escribir
    unblocked = await client.post("/api/v1/inventory/categories", json={"name": "Dulces"}, headers=owner)
    assert unblocked.status_code == 201, unblocked.text

    # CA-P8: el Dueño ve qué se hizo y por qué
    activity = (await client.get("/api/v1/subscription/activity", headers=owner)).json()
    assert activity[0]["summary"] == "Confirmamos tu pago de $199.00 en efectivo. Tu cuenta volvió a estar activa."
    assert activity[0]["reason"] == reason
    assert activity[0]["by"] == "Soporte Nexus · Operadora de Prueba"

    # El middleware abrió conexiones del pool global: se liberan para otros tests
    await engine.dispose()


@pytest.mark.asyncio
async def test_manual_status_change_and_courtesy_month(client: AsyncClient, db_session: AsyncSession):
    _, headers, _ = await _enrolled_session(client, db_session)
    _, tenant_id, _ = await _register_store(client, "estado")

    same = await client.post(
        f"{P}/tenants/{tenant_id}/status",
        json={"status": "ACTIVE", "reason": "Sin cambio, sólo probando."},
        headers=headers,
    )
    assert same.status_code == 422

    locked = await client.post(
        f"{P}/tenants/{tenant_id}/status",
        json={"status": "HARD_LOCK", "reason": "Dos meses sin pago y sin respuesta a los avisos."},
        headers=headers,
    )
    assert locked.status_code == 200 and locked.json()["status"] == "HARD_LOCK"

    courtesy = await client.post(
        f"{P}/tenants/{tenant_id}/courtesy",
        json={"reason": "Compensación por la caída del servicio del 20 de septiembre."},
        headers=headers,
    )
    assert courtesy.status_code == 200, courtesy.text
    body = courtesy.json()
    assert body["status"] == "ACTIVE"
    gift = body["invoices"][0]
    assert gift["payment_method"] == "COURTESY"
    assert Decimal(gift["amount_mxn"]) == Decimal("0.00")
    assert gift["status"] == "PAID"


@pytest.mark.asyncio
async def test_plan_downgrade_blocked_when_store_exceeds_user_limit(client: AsyncClient, db_session: AsyncSession):
    _, headers, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, _ = await _register_store(client, "plan")

    up = await client.post(
        f"{P}/tenants/{tenant_id}/plan",
        json={"plan": "COMERCIO", "reason": "Pidió subir de plan por teléfono."},
        headers=headers,
    )
    assert up.status_code == 200 and up.json()["plan"] == "COMERCIO"

    roles = (await client.get("/api/v1/roles", headers=owner)).json()
    cashier = next(r for r in roles if r["name"] == "CASHIER")
    for i in range(2):
        created = await client.post(
            "/api/v1/users",
            json={"email": f"cajero{i}_{uuid.uuid4().hex[:6]}@tienda.mx", "password": "empleado123",
                  "full_name": f"Cajero {i}", "role_id": cashier["id"]},
            headers=owner,
        )
        assert created.status_code == 201, created.text

    down = await client.post(
        f"{P}/tenants/{tenant_id}/plan",
        json={"plan": "EMPRENDEDOR", "reason": "Pidió bajar de plan para ahorrar."},
        headers=headers,
    )
    assert down.status_code == 422
    assert "3 activos" in down.json()["detail"]


@pytest.mark.asyncio
async def test_cashier_cannot_read_support_activity(client: AsyncClient):
    owner, _, _ = await _register_store(client, "cajero")
    roles = (await client.get("/api/v1/roles", headers=owner)).json()
    cashier_role = next(r for r in roles if r["name"] == "CASHIER")
    email = f"caj_{uuid.uuid4().hex[:6]}@tienda.mx"
    await client.post(
        "/api/v1/users",
        json={"email": email, "password": "empleado123", "full_name": "Cajero", "role_id": cashier_role["id"]},
        headers=owner,
    )
    login = await client.post("/api/v1/auth/login", json={"email": email, "password": "empleado123"})
    cashier = {"Authorization": f"Bearer {login.json()['access_token']}"}
    assert (await client.get("/api/v1/subscription/activity", headers=cashier)).status_code == 403


@pytest.mark.asyncio
async def test_metrics_and_open_invoices_inbox(client: AsyncClient, db_session: AsyncSession):
    _, headers, _ = await _enrolled_session(client, db_session)
    _, tenant_id, _ = await _register_store(client, "bandeja")
    invoice_id = await _overdue_invoice(db_session, tenant_id, TenantStatus.SOFT_LOCK)

    metrics = (await client.get(f"{P}/metrics", headers=headers)).json()
    assert metrics["tenants_total"] >= 1
    assert metrics["open_invoices"] >= 1
    assert Decimal(metrics["mrr_mxn"]) > 0

    inbox = (await client.get(f"{P}/invoices/open", params={"limit": 200}, headers=headers)).json()
    assert str(invoice_id) in [i["id"] for i in inbox["items"]]


# -----------------------------------------------------------------------------
# Bitácora inalterable (CA-P6)
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_audit_log_rejects_updates_and_deletes(client: AsyncClient, db_session: AsyncSession):
    await _enrolled_session(client, db_session)
    for statement in (
        "UPDATE platform_audit_log SET reason = 'reescrito' WHERE id = (SELECT max(id) FROM platform_audit_log)",
        "DELETE FROM platform_audit_log WHERE id = (SELECT max(id) FROM platform_audit_log)",
    ):
        with pytest.raises(Exception) as err:
            await db_session.execute(text(statement))
        assert "sólo anexar" in str(err.value)
        await db_session.rollback()


@pytest.mark.asyncio
async def test_chain_verification_detects_tampering(client: AsyncClient, db_session: AsyncSession):
    """Aun si alguien apaga el trigger desde la base, la cadena delata el cambio."""
    _, headers, _ = await _enrolled_session(client, db_session)
    intact = (await client.get(f"{P}/audit/verify", headers=headers)).json()
    assert intact["intact"] is True and intact["checked"] >= 1

    # Todo dentro de una transacción que se revierte: la base queda como estaba
    await db_session.execute(text("ALTER TABLE platform_audit_log DISABLE TRIGGER trg_platform_audit_log_immutable"))
    target = (await db_session.execute(text("SELECT max(id) FROM platform_audit_log"))).scalar_one()
    await db_session.execute(text("UPDATE platform_audit_log SET reason = 'alterado' WHERE id = :id"), {"id": target})
    tampered = (await client.get(f"{P}/audit/verify", headers=headers)).json()
    await db_session.rollback()

    assert tampered["intact"] is False
    assert tampered["broken_at_id"] == target


# -----------------------------------------------------------------------------
# Arquitectura: el panel no importa dominios de contenido (P2)
# -----------------------------------------------------------------------------

def test_platform_module_does_not_import_tenant_content():
    import ast
    import pathlib

    forbidden = (
        "app.modules.inventory", "app.modules.sales_pos", "app.modules.customers_credit",
        "app.modules.purchasing_suppliers", "app.modules.cash_treasury", "app.modules.analytics_reports",
        "app.modules.whatsapp_catalog", "app.modules.community_catalog",
    )
    root = pathlib.Path(__file__).resolve().parents[2] / "app" / "modules" / "platform_admin"
    offenders = []
    for path in root.rglob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            names = []
            if isinstance(node, ast.ImportFrom) and node.module:
                names = [node.module]
            elif isinstance(node, ast.Import):
                names = [alias.name for alias in node.names]
            offenders += [f"{path.name}: {n}" for n in names if n.startswith(forbidden)]
    assert offenders == []


def test_support_activity_speaks_like_the_shopkeeper():
    from app.modules.platform_admin.domain.audit_log import PlatformAuditLog
    from app.modules.platform_admin.services.tenant_activity import describe

    courtesy = PlatformAuditLog(action="COURTESY_GRANTED", details={"periodo": "2026-12-15 a 2027-01-14", "reactivado": False})
    assert describe(courtesy) == "Te dimos un mes sin costo (15 dic 2026 a 14 ene 2027)."
    same_year = PlatformAuditLog(action="COURTESY_GRANTED", details={"periodo": "2026-09-28 a 2026-10-27", "reactivado": True})
    assert describe(same_year) == "Te dimos un mes sin costo (28 sep a 27 oct 2026). Tu cuenta volvió a estar activa."
    status_change = PlatformAuditLog(action="STATUS_CHANGED", details={"de": "SOFT_LOCK", "a": "ACTIVE"})
    assert describe(status_change) == "Tu cuenta pasó de sólo lectura a activa."
