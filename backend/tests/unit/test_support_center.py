"""
Centro de soporte — etapa 1, backend (Sep 2026). Un test por criterio:
CA-S1 recuperación automática · CA-S2 recuperación asistida · CA-S3 regalar días
· CA-S4 suspensión por abuso · CA-S5 exportación · CA-S6 eliminación de dos
personas · CA-S7 acceso de soporte concedido por el dueño · feed del día.

Los correos salen por el transporte `console` y se leen de `console_outbox`.
"""
import io
import re
import uuid
import zipfile
from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import engine
from app.core.email.sender import console_outbox
from app.modules.auth_tenancy.domain.login_code import LoginCode
from app.modules.auth_tenancy.domain.tenant import Tenant
from test_platform_admin import P, _enrolled_session, _register_store

CODE = re.compile(r"\b([A-Z2-9]{4}-[A-Z2-9]{4})\b")
REASON = "El dueño lo pidió por WhatsApp el 28 de septiembre."
CHECKS = {"store_name": True, "owner_email": True, "signup_date": True, "employees": True}


@pytest.fixture(autouse=True)
def _clean_outbox():
    console_outbox.clear()
    yield
    console_outbox.clear()


def _mail_to(email: str):
    return [m for m in console_outbox if m.to_email == email]


def _code_in(mail) -> str:
    match = CODE.search(mail.text)
    assert match, mail.text
    return match.group(1)


def _auth(body: dict) -> dict:
    return {"Authorization": f"Bearer {body['access_token']}"}


# -----------------------------------------------------------------------------
# CA-S1 — "¿Olvidaste tu contraseña?"
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_self_recovery_by_email_forces_a_new_password(client: AsyncClient):
    _, _, email = await _register_store(client, "olvido")

    unknown = await client.post("/api/v1/auth/password-recovery", json={"email": "nadie_x@tienda.mx"})
    asked = await client.post("/api/v1/auth/password-recovery", json={"email": email})
    assert asked.status_code == unknown.status_code == 202
    assert asked.json() == unknown.json()  # no delata qué correos existen
    assert _mail_to("nadie_x@tienda.mx") == []
    [mail] = _mail_to(email)
    code = _code_in(mail)

    wrong = await client.post("/api/v1/auth/login-with-code", json={"email": email, "code": "AAAA-AAAA"})
    assert wrong.status_code == 401

    session = await client.post("/api/v1/auth/login-with-code", json={"email": email, "code": code.lower()})
    assert session.status_code == 200, session.text
    assert session.json()["user"]["must_change_password"] is True
    headers = _auth(session.json())

    # Hasta poner contraseña nueva, sólo /auth/me y /auth/set-password
    blocked = await client.get("/api/v1/inventory/products", headers=headers)
    assert blocked.status_code == 403
    assert blocked.json()["error"]["code"] == "PASSWORD_CHANGE_REQUIRED"
    assert (await client.get("/api/v1/auth/me", headers=headers)).status_code == 200

    short = await client.post("/api/v1/auth/set-password", json={"new_password": "corta"}, headers=headers)
    assert short.status_code == 422
    done = await client.post("/api/v1/auth/set-password", json={"new_password": "NuevaClave2026"}, headers=headers)
    assert done.status_code == 204, done.text
    assert (await client.get("/api/v1/inventory/products", headers=headers)).status_code == 200

    # El código era de un solo uso y la contraseña nueva es la que vale
    again = await client.post("/api/v1/auth/login-with-code", json={"email": email, "code": code})
    assert again.status_code == 401
    login = await client.post("/api/v1/auth/login", json={"email": email, "password": "NuevaClave2026"})
    assert login.status_code == 200
    assert login.json()["user"]["must_change_password"] is False
    # set-password no sirve sin el cambio pendiente (no pide la actual)
    again_set = await client.post(
        "/api/v1/auth/set-password", json={"new_password": "OtraClave2026"}, headers=_auth(login.json()),
    )
    assert again_set.status_code == 400


@pytest.mark.asyncio
async def test_self_recovery_is_rate_limited_and_codes_die_after_five_misses(client: AsyncClient):
    _, _, email = await _register_store(client, "tope")
    for _ in range(4):
        assert (await client.post("/api/v1/auth/password-recovery", json={"email": email})).status_code == 202
    mails = _mail_to(email)
    assert len(mails) == 3  # el cuarto se ignora en silencio
    latest = _code_in(mails[-1])
    # Pedir otro invalidó los anteriores
    first = _code_in(mails[0])
    if first != latest:
        assert (await client.post("/api/v1/auth/login-with-code", json={"email": email, "code": first})).status_code == 401

    for _ in range(4):
        await client.post("/api/v1/auth/login-with-code", json={"email": email, "code": "ZZZZ-ZZZZ"})
    # El intento que lleva la cuenta a 5 fallos (incluido el del código viejo) mata el código
    await client.post("/api/v1/auth/login-with-code", json={"email": email, "code": "ZZZZ-ZZZZ"})
    dead = await client.post("/api/v1/auth/login-with-code", json={"email": email, "code": latest})
    assert dead.status_code == 401


# -----------------------------------------------------------------------------
# CA-S2 — Recuperación asistida
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_assisted_recovery_requires_validation_and_operator_never_sees_the_code(
    client: AsyncClient, db_session: AsyncSession
):
    _, headers, _ = await _enrolled_session(client, db_session)
    _, tenant_id, email = await _register_store(client, "asistida")
    url = f"{P}/tenants/{tenant_id}/assisted-recovery"

    incomplete = await client.post(url, json={"reason": REASON, "checks": {**CHECKS, "employees": False}}, headers=headers)
    assert incomplete.status_code == 422
    assert "empleados" in incomplete.json()["detail"]
    assert _mail_to(email) == []

    # Si paga con Google Play, el número de orden es obligatorio
    tenant = (await db_session.execute(select(Tenant).where(Tenant.id == tenant_id))).scalar_one()
    tenant.subscription_source = "GOOGLE_PLAY"
    await db_session.commit()
    no_order = await client.post(url, json={"reason": REASON, "checks": CHECKS}, headers=headers)
    assert no_order.status_code == 422 and "GPA" in no_order.json()["detail"]

    sent = await client.post(
        url, json={"reason": REASON, "checks": CHECKS, "google_order_id": "GPA.3312-4455-6677-88990"}, headers=headers,
    )
    assert sent.status_code == 200, sent.text
    [mail] = _mail_to(email)
    code = _code_in(mail)
    assert "Soporte Nexus" in mail.text
    assert code not in sent.text and email not in sent.text
    assert sent.json()["sent_to"].endswith("@tienda.mx") and "•" in sent.json()["sent_to"]
    row = (await db_session.execute(
        select(LoginCode).where(LoginCode.tenant_id == tenant_id).order_by(LoginCode.created_at.desc())
    )).scalars().first()
    assert row.origin == "ASSISTED"
    assert abs((row.expires_at - row.created_at) - timedelta(hours=24)) < timedelta(minutes=1)
    assert code not in row.code_hash

    # En el panel: sigue "sin usar" hasta que el dueño entra
    feed = (await client.get(f"{P}/feed", headers=headers)).json()
    assert any(a["kind"] == "ASSISTED_CODE_UNUSED" and a["tenant_id"] == str(tenant_id) for a in feed["attention"])
    detail = (await client.get(f"{P}/tenants/{tenant_id}", headers=headers)).json()
    assert detail["support"]["assisted_code_until"] is not None
    [sent] = [a for a in detail["activity"] if a["action"] == "ASSISTED_RECOVERY_SENT"]
    assert sent["details"]["orden_google"] == "GPA.3312-4455-6677-88990"
    assert sent["summary"].startswith("Operadora de Prueba envió un código de recuperación")
    # La ficha no se llena de "abrió la ficha" (ruido del feed)
    assert not any(a["action"] == "TENANT_VIEWED" for a in detail["activity"])
    # En la bitácora general cada acción dice su tienda; sin ruido si se pide
    page = (await client.get(f"{P}/audit", params={"tenant_id": str(tenant_id)}, headers=headers)).json()["items"]
    [logged] = [a for a in page if a["action"] == "ASSISTED_RECOVERY_SENT"]
    assert "una tienda" not in logged["summary"] and "Abarrotes" in logged["summary"]
    quiet = (await client.get(f"{P}/audit", params={"tenant_id": str(tenant_id), "exclude_noise": "true"},
                              headers=headers)).json()["items"]
    assert quiet and not any(a["action"] == "TENANT_VIEWED" for a in quiet)
    assert any(a["action"] == "TENANT_VIEWED" for a in page)
    assert code not in str(detail)

    owner = await client.post("/api/v1/auth/login-with-code", json={"email": email, "code": code})
    assert owner.status_code == 200
    feed = (await client.get(f"{P}/feed", headers=headers)).json()
    assert not any(a["kind"] == "ASSISTED_CODE_UNUSED" and a["tenant_id"] == str(tenant_id) for a in feed["attention"])


# -----------------------------------------------------------------------------
# CA-S3 — Regalar días, con "Así lo verá la tienda"
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_gift_days_extends_and_owner_sees_exactly_the_preview(client: AsyncClient, db_session: AsyncSession):
    _, headers, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, _ = await _register_store(client, "dias")
    reason = "Compensación por la caída del servicio del 20 de septiembre."

    preview = (await client.post(
        f"{P}/tenants/{tenant_id}/preview", json={"action": "DAYS_GIFTED", "days": 7, "reason": reason}, headers=headers,
    )).json()
    gift = await client.post(f"{P}/tenants/{tenant_id}/gift-days", json={"days": 7, "reason": reason}, headers=headers)
    assert gift.status_code == 200, gift.text

    [seen] = [a for a in (await client.get("/api/v1/subscription/activity", headers=owner)).json()]
    assert seen["summary"] == preview["summary"]
    assert seen["summary"].startswith("Te regalamos 7 días: tu suscripción vale hasta el ")
    assert seen["reason"] == preview["reason"] == reason
    assert seen["by"] == preview["by"] == "Soporte Nexus · Operadora de Prueba"

    too_many = await client.post(f"{P}/tenants/{tenant_id}/gift-days", json={"days": 91, "reason": reason}, headers=headers)
    assert too_many.status_code == 422


# -----------------------------------------------------------------------------
# CA-S4 — Suspensión por abuso ≠ falta de pago
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_abuse_suspension_is_distinct_and_not_lifted_by_gifts(client: AsyncClient, db_session: AsyncSession):
    _, headers, _ = await _enrolled_session(client, db_session)
    earlier, tenant_id, email = await _register_store(client, "abuso")
    reason = "Vitrina web con productos prohibidos, reportada por usuarios."

    suspended = await client.post(f"{P}/tenants/{tenant_id}/suspension", json={"reason": reason}, headers=headers)
    assert suspended.status_code == 200, suspended.text
    # Un token emitido antes de la suspensión (dice ACTIVE) tampoco lee: efecto inmediato
    stale = await client.get("/api/v1/inventory/products", headers=earlier)
    assert stale.status_code == 402 and stale.json()["error"]["details"]["lock_reason"] == "ABUSE"
    assert (await client.get("/api/v1/subscription", headers=earlier)).status_code == 200
    assert suspended.json()["status"] == "HARD_LOCK" and suspended.json()["lock_reason"] == "ABUSE"
    assert suspended.json()["suspension_reason"] == reason
    twice = await client.post(f"{P}/tenants/{tenant_id}/suspension", json={"reason": reason}, headers=headers)
    assert twice.status_code == 422

    # El dueño entra (para leer por qué) y la app sabe que no es falta de pago
    login = await client.post("/api/v1/auth/login", json={"email": email, "password": "password123"})
    owner = _auth(login.json())
    sub = (await client.get("/api/v1/subscription", headers=owner)).json()
    assert sub["lock_reason"] == "ABUSE" and sub["suspension_reason"] == reason
    blocked = await client.get("/api/v1/inventory/products", headers=owner)
    assert blocked.status_code == 402
    assert blocked.json()["error"]["details"]["lock_reason"] == "ABUSE"
    assert "Soporte Nexus suspendió" in blocked.json()["error"]["message"]

    # Ni regalar días la levanta
    gift = await client.post(f"{P}/tenants/{tenant_id}/gift-days", json={"days": 5, "reason": reason}, headers=headers)
    assert gift.json()["status"] == "HARD_LOCK" and gift.json()["lock_reason"] == "ABUSE"

    feed = (await client.get(f"{P}/feed", headers=headers)).json()
    assert any(a["kind"] == "ABUSE_SUSPENSION" and a["tenant_id"] == str(tenant_id) for a in feed["attention"])

    lifted = await client.post(
        f"{P}/tenants/{tenant_id}/suspension/lift", json={"reason": "Retiró los productos y aclaró el caso."}, headers=headers,
    )
    assert lifted.json()["status"] == "ACTIVE" and lifted.json()["lock_reason"] is None
    assert (await client.get("/api/v1/inventory/products", headers=owner)).status_code == 200
    summaries = [a["summary"] for a in (await client.get("/api/v1/subscription/activity", headers=owner)).json()]
    assert summaries[0] == "Levantamos la suspensión: tu cuenta está activa."
    assert summaries[-1].startswith("Suspendimos tu cuenta")

    await engine.dispose()


# -----------------------------------------------------------------------------
# CA-S5 — Exportación al correo del dueño
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_export_reaches_the_owner_email_and_never_the_operator(client: AsyncClient, db_session: AsyncSession):
    _, headers, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, email = await _register_store(client, "exporta")
    other, _, _ = await _register_store(client, "ajena")
    await client.post("/api/v1/inventory/products", json={"name": "Coca-Cola 600ml", "price_mxn": "18.00"}, headers=owner)
    await client.post("/api/v1/inventory/products", json={"name": "Producto Ajeno XYZ", "price_mxn": "5.00"}, headers=other)

    resp = await client.post(f"{P}/tenants/{tenant_id}/export", json={"reason": REASON}, headers=headers)
    assert resp.status_code == 202, resp.text
    assert "coca" not in resp.text.lower()

    [mail] = _mail_to(email)
    [attachment] = mail.attachments
    archive = zipfile.ZipFile(io.BytesIO(attachment.content))
    names = archive.namelist()
    assert "products.csv" in names and "LEEME.txt" in names and "tenants.csv" in names
    products = archive.read("products.csv").decode("utf-8-sig")
    assert "Coca-Cola 600ml" in products and "Producto Ajeno XYZ" not in products
    users = archive.read("users.csv").decode("utf-8-sig")
    assert "hashed_password" not in users and email in users
    assert "login_codes.csv" not in names

    detail = (await client.get(f"{P}/tenants/{tenant_id}", headers=headers)).json()
    assert detail["support"]["last_export"]["status"] == "SENT"
    assert "coca" not in str(detail).lower()
    activity = (await client.get("/api/v1/subscription/activity", headers=owner)).json()
    assert [a["action"] for a in activity[:2]] == ["DATA_EXPORT_SENT", "DATA_EXPORT_REQUESTED"]

    await engine.dispose()


# -----------------------------------------------------------------------------
# CA-S6 — Eliminar la tienda exige dos fundadores
# -----------------------------------------------------------------------------

async def _store_with_history(client: AsyncClient, prefix: str):
    """Tienda con venta, compra recibida, proveedor y empleado: las llaves RESTRICT que rompen un borrado ingenuo."""
    owner, tenant_id, email = await _register_store(client, prefix)
    warehouse = (await client.get("/api/v1/inventory/warehouses", headers=owner)).json()[0]["id"]
    product = (await client.post(
        "/api/v1/inventory/products",
        json={"name": "Galletas", "price_mxn": "18.00", "initial_stock": "20", "warehouse_id": warehouse},
        headers=owner,
    )).json()
    sale = await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse,
            "items": [{"product_id": product["id"], "quantity": 2, "unit_price_mxn": 18.00, "discount_mxn": 0}],
            "discount_mxn": 0,
        },
        headers=owner,
    )
    assert sale.status_code == 201, sale.text
    supplier = (await client.post("/api/v1/suppliers", json={"name": "Bimbo"}, headers=owner)).json()
    order = (await client.post(
        "/api/v1/purchase-orders",
        json={"supplier_id": supplier["id"], "items": [{"product_id": product["id"], "quantity_ordered": 5, "unit_cost_mxn": 9}]},
        headers=owner,
    )).json()
    received = await client.post(
        f"/api/v1/purchase-orders/{order['id']}/receive",
        json={"items_received": [{"purchase_order_item_id": order["items"][0]["id"], "quantity_received": 5}]},
        headers=owner,
    )
    assert received.status_code == 200, received.text
    case = await client.post(
        "/api/v1/support/cases",
        json={"topic_key": "other", "description": "Quiero cerrar la tienda y borrar mis datos."},
        headers=owner,
    )
    assert case.status_code == 201, case.text
    return owner, tenant_id, email


@pytest.mark.asyncio
async def test_deleting_a_store_takes_two_founders_and_removes_everything(client: AsyncClient, db_session: AsyncSession):
    _, alan, _ = await _enrolled_session(client, db_session)
    _, eduardo, _ = await _enrolled_session(client, db_session)
    _, tenant_id, email = await _store_with_history(client, "borrar")
    slug = (await client.get(f"{P}/tenants/{tenant_id}", headers=alan)).json()["slug"]
    reason = "El dueño cerró la tienda y pidió borrar sus datos (LFPDPPP)."

    wrong = await client.post(f"{P}/tenants/{tenant_id}/deletion", json={"reason": reason, "confirm_slug": "otra"}, headers=alan)
    assert wrong.status_code == 422

    asked = await client.post(f"{P}/tenants/{tenant_id}/deletion", json={"reason": reason, "confirm_slug": slug}, headers=alan)
    assert asked.status_code == 201, asked.text
    request_id = asked.json()["id"]
    dup = await client.post(f"{P}/tenants/{tenant_id}/deletion", json={"reason": reason, "confirm_slug": slug}, headers=alan)
    assert dup.status_code == 409

    # El que la pidió no puede aprobarla
    self_approve = await client.post(f"{P}/approvals/{request_id}/approve", json={"reason": reason}, headers=alan)
    assert self_approve.status_code == 403

    # Al otro le aparece en el feed como "te toca"
    feed = (await client.get(f"{P}/feed", headers=eduardo)).json()
    mine = [a for a in feed["attention"] if a["ref_id"] == request_id]
    assert mine and mine[0]["awaiting_you"] is True and feed["attention"][0]["awaiting_you"] is True
    theirs = [a for a in (await client.get(f"{P}/feed", headers=alan)).json()["attention"] if a["ref_id"] == request_id]
    assert theirs[0]["awaiting_you"] is False

    approved = await client.post(
        f"{P}/approvals/{request_id}/approve", json={"reason": "Confirmado con el dueño por teléfono."}, headers=eduardo,
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["status"] == "APPROVED"

    assert (await client.get(f"{P}/tenants/{tenant_id}", headers=alan)).status_code == 404
    login = await client.post("/api/v1/auth/login", json={"email": email, "password": "password123"})
    assert login.status_code == 401
    await db_session.execute(text("SELECT set_config('app.bypass_rls', 'on', true)"))
    for table in ("sales", "products", "suppliers", "purchase_orders", "users", "warehouses",
                  "support_cases", "support_case_messages"):
        left = (await db_session.execute(text(f"SELECT count(*) FROM {table} WHERE tenant_id = :t"), {"t": tenant_id})).scalar_one()
        assert left == 0, table
    await db_session.rollback()

    [notice] = _mail_to(email)
    assert "eliminamos" in notice.text.lower()
    audit = (await client.get(f"{P}/audit", params={"tenant_id": str(tenant_id)}, headers=alan)).json()["items"]
    deleted = next(e for e in audit if e["action"] == "TENANT_DELETED")
    assert deleted["details"]["slug"] == slug and email not in str(deleted)
    # Queda la huella en la bitácora íntegra
    assert (await client.get(f"{P}/audit/verify", headers=alan)).json()["intact"] is True


@pytest.mark.asyncio
async def test_a_deletion_can_be_cancelled_and_expires(client: AsyncClient, db_session: AsyncSession):
    _, alan, _ = await _enrolled_session(client, db_session)
    _, eduardo, _ = await _enrolled_session(client, db_session)
    _, tenant_id, _ = await _register_store(client, "cancelar")
    slug = (await client.get(f"{P}/tenants/{tenant_id}", headers=alan)).json()["slug"]
    body = {"reason": "Pedido por el dueño, luego se arrepintió.", "confirm_slug": slug}

    first = (await client.post(f"{P}/tenants/{tenant_id}/deletion", json=body, headers=alan)).json()
    cancelled = await client.post(f"{P}/approvals/{first['id']}/cancel", json={"reason": "El dueño decidió seguir."}, headers=eduardo)
    assert cancelled.json()["status"] == "CANCELLED"
    late = await client.post(f"{P}/approvals/{first['id']}/approve", json={"reason": "Ya no debería pasar."}, headers=eduardo)
    assert late.status_code == 422

    second = (await client.post(f"{P}/tenants/{tenant_id}/deletion", json=body, headers=alan)).json()
    await db_session.execute(
        text("UPDATE platform_approval_requests SET expires_at = now() - interval '1 minute' WHERE id = :id"),
        {"id": second["id"]},
    )
    await db_session.commit()
    expired = await client.post(f"{P}/approvals/{second['id']}/approve", json={"reason": "Tarde, ya venció."}, headers=eduardo)
    assert expired.status_code == 422
    assert (await client.get(f"{P}/tenants/{tenant_id}", headers=alan)).status_code == 200
    # Una vencida no impide pedirla de nuevo
    third = await client.post(f"{P}/tenants/{tenant_id}/deletion", json=body, headers=alan)
    assert third.status_code == 201


# -----------------------------------------------------------------------------
# CA-S7 — Acceso de soporte: sólo si el dueño lo concede, y vence
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_only_the_owner_grants_support_access_and_it_expires(client: AsyncClient, db_session: AsyncSession):
    _, headers, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, _ = await _register_store(client, "concede")

    assert (await client.get("/api/v1/support-access", headers=owner)).json()["active"] is None
    detail = (await client.get(f"{P}/tenants/{tenant_id}", headers=headers)).json()
    assert detail["support"]["access_granted_until"] is None

    bad = await client.post("/api/v1/support-access", json={"hours": 5}, headers=owner)
    assert bad.status_code == 422
    granted = await client.post("/api/v1/support-access", json={"hours": 24}, headers=owner)
    assert granted.status_code == 200, granted.text
    until = datetime.fromisoformat(granted.json()["active"]["expires_at"])
    assert abs((until - datetime.now(timezone.utc)) - timedelta(hours=24)) < timedelta(minutes=2)

    feed = (await client.get(f"{P}/feed", headers=headers)).json()
    assert any(a["kind"] == "SUPPORT_ACCESS_ACTIVE" and a["tenant_id"] == str(tenant_id) for a in feed["attention"])
    assert any(e["summary"].endswith("concedió acceso de soporte por 24 h") for e in feed["events"])

    # Un cajero no decide quién entra a los datos de su patrón
    roles = (await client.get("/api/v1/roles", headers=owner)).json()
    cashier_role = next(r for r in roles if r["name"] == "CASHIER")
    email = f"caj_{uuid.uuid4().hex[:6]}@tienda.mx"
    await client.post(
        "/api/v1/users",
        json={"email": email, "password": "empleado123", "full_name": "Cajero", "role_id": cashier_role["id"]},
        headers=owner,
    )
    cashier = _auth((await client.post("/api/v1/auth/login", json={"email": email, "password": "empleado123"})).json())
    assert (await client.post("/api/v1/support-access", json={"hours": 1}, headers=cashier)).status_code == 403

    revoked = (await client.delete("/api/v1/support-access", headers=owner)).json()
    assert revoked["active"] is None and revoked["history"][0]["revoked_at"] is not None
    detail = (await client.get(f"{P}/tenants/{tenant_id}", headers=headers)).json()
    assert detail["support"]["access_granted_until"] is None


# -----------------------------------------------------------------------------
# Ficha y feed
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_tenant_card_diagnostics_are_metadata_only(client: AsyncClient, db_session: AsyncSession):
    _, headers, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, email = await _register_store(client, "diagnostico")
    await client.get("/api/v1/inventory/warehouses", headers=owner)  # crea el almacén principal
    await client.post("/api/v1/inventory/products", json={"name": "Coca-Cola 600ml", "price_mxn": "18.00"}, headers=owner)

    detail = await client.get(f"{P}/tenants/{tenant_id}", headers=headers)
    body = detail.json()
    diag = body["diagnostics"]
    assert diag["users"][0]["email"] == email and diag["users"][0]["role"] == "OWNER"
    assert diag["warehouses"] and diag["warehouses"][0]["is_default"] is True
    assert "catalog_enabled" in diag
    assert "coca" not in detail.text.lower() and "invoices" not in body


@pytest.mark.asyncio
async def test_feed_lists_what_happened_without_noise(client: AsyncClient, db_session: AsyncSession):
    _, headers, _ = await _enrolled_session(client, db_session)
    _, tenant_id, _ = await _register_store(client, "feed")
    await client.get(f"{P}/tenants/{tenant_id}", headers=headers)  # TENANT_VIEWED: ruido
    await client.post(
        f"{P}/tenants/{tenant_id}/gift-days", json={"days": 1, "reason": "Día extra por la falla del lunes."}, headers=headers,
    )

    feed = (await client.get(f"{P}/feed", headers=headers)).json()
    mine = [e for e in feed["events"] if e["tenant_id"] == str(tenant_id)]
    assert [e["kind"] for e in mine] == ["AUDIT", "SIGNUP"]
    assert mine[0]["summary"].startswith("Operadora de Prueba regaló 1 día a Abarrotes feed")
    assert mine[0]["reason"] == "Día extra por la falla del lunes."
    assert not any(e["action"] in ("TENANT_VIEWED", "LOGIN_SUCCEEDED") for e in feed["events"])

    # "Ver anteriores": un rango que termina antes de todo esto no lo trae
    earlier = (await client.get(
        f"{P}/feed",
        params={"until": (datetime.now(timezone.utc) - timedelta(days=3)).isoformat()},
        headers=headers,
    )).json()
    assert not any(e["tenant_id"] == str(tenant_id) for e in earlier["events"])
