"""
Centro de soporte — etapa 4a: sesión de soporte de sólo lectura (P37–P39).

CA-S7.1 sin concesión no hay sesión · CA-S7.2 ninguna escritura pasa, ni
llamando al servidor directo · CA-S7.3 retirar la concesión corta en la
siguiente petición · CA-S7.4 vence a los 30 min (o la extensión) o al vencer la
concesión · CA-S7.5 el dueño ve quién, cuándo, cuánto, por qué y qué secciones.
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect
from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.main import app
from test_platform_admin import P, _enrolled_session, _register_store

S = "/api/v1/support-session"
REASON = "Revisar por qué no le cuadra el inventario de refrescos."


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _sql(db: AsyncSession, statement: str, **params) -> None:
    """Mueve fechas para probar vencimientos (salta RLS sólo en esta transacción)."""
    await db.execute(text("SELECT set_config('app.bypass_rls', 'on', true)"))
    await db.execute(text(statement), params)
    await db.commit()


async def _granted_store(client: AsyncClient, prefix: str, hours: int = 1):
    owner, tenant_id, email = await _register_store(client, prefix)
    granted = await client.post("/api/v1/support-access", json={"hours": hours}, headers=owner)
    assert granted.status_code == 200, granted.text
    return owner, tenant_id, email


async def _open(client: AsyncClient, panel: dict, tenant_id, reason: str = REASON):
    started = await client.post(f"{P}/tenants/{tenant_id}/support-sessions", json={"reason": reason}, headers=panel)
    assert started.status_code == 201, started.text
    body = started.json()
    opened = await client.post(f"{S}/open", json={"code": body["link_code"]})
    assert opened.status_code == 200, opened.text
    return body, opened.json()


# -----------------------------------------------------------------------------
# CA-S7.1 — Sin concesión no hay sesión
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_no_session_without_the_owners_permission(client: AsyncClient, db_session: AsyncSession):
    _, panel, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, _ = await _register_store(client, "sinpermiso")
    url = f"{P}/tenants/{tenant_id}/support-sessions"

    denied = await client.post(url, json={"reason": REASON}, headers=panel)
    assert denied.status_code == 409
    assert "no ha dado acceso" in denied.json()["error"]["message"]
    assert (await client.post(url, json={"reason": "corto"}, headers=panel)).status_code == 422

    await client.post("/api/v1/support-access", json={"hours": 1}, headers=owner)
    other_case = uuid.uuid4()
    assert (await client.post(url, json={"reason": REASON, "case_id": str(other_case)}, headers=panel)).status_code == 422

    started = await client.post(url, json={"reason": REASON}, headers=panel)
    assert started.status_code == 201, started.text
    body = started.json()
    assert body["session"]["state"] == "WAITING_OPEN" and len(body["link_code"]) >= 40
    link_until = datetime.fromisoformat(body["link_expires_at"])
    assert timedelta(minutes=9) < link_until - datetime.now(timezone.utc) <= timedelta(minutes=10)
    # Una sesión vigente por operador y tienda: la siguiente se pide con «Abrir de nuevo»
    again = await client.post(url, json={"reason": REASON}, headers=panel)
    assert again.status_code == 409 and "Abrir de nuevo" in again.json()["error"]["message"]

    # Un token de comercio no abre sesiones (otra llave y otra audiencia)
    assert (await client.post(url, json={"reason": REASON}, headers=owner)).status_code == 401


# -----------------------------------------------------------------------------
# CA-S7.2 — Ve lo que ve el dueño y no escribe nada
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_support_session_reads_like_the_owner_and_never_writes(client: AsyncClient, db_session: AsyncSession):
    _, panel, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, email = await _granted_store(client, "lectura")
    await client.get("/api/v1/inventory/warehouses", headers=owner)
    await client.post("/api/v1/inventory/products", json={"name": "Coca-Cola 600ml", "price_mxn": "18.00"}, headers=owner)

    started, opened = await _open(client, panel, tenant_id)
    support = _auth(opened["access_token"])
    status = opened["status"]
    assert status["reason"] == REASON and status["operator_name"] == "Operadora de Prueba"
    assert status["can_extend"] is False
    assert timedelta(minutes=29) < datetime.fromisoformat(status["expires_at"]) - datetime.now(timezone.utc) <= timedelta(minutes=30)

    # El enlace era de un solo uso
    reused = await client.post(f"{S}/open", json={"code": started["link_code"]})
    assert reused.status_code == 410 and reused.json()["error"]["code"] == "SUPPORT_LINK_INVALID"

    me = (await client.get("/api/v1/auth/me", headers=support)).json()
    assert me["email"] == email
    products = await client.get("/api/v1/inventory/products", headers=support)
    assert products.status_code == 200 and "Coca-Cola" in products.text

    # Ninguna escritura, sea cual sea la ruta
    for method, path, body in [
        ("POST", "/api/v1/inventory/categories", {"name": "Refrescos"}),
        ("POST", "/api/v1/sales/checkout", {}),
        ("POST", "/api/v1/support-access", {"hours": 72}),
        ("DELETE", "/api/v1/support-access", None),
        ("PUT", "/api/v1/inventory/products/x", {}),
        ("PATCH", "/api/v1/users/x", {}),
    ]:
        resp = await client.request(method, path, json=body, headers=support)
        assert resp.status_code == 403, (method, path, resp.text)
        assert resp.json()["error"]["code"] == "SUPPORT_READ_ONLY"
    # Ni respaldos ni salud del sistema, aunque sean lecturas
    backups = await client.get("/api/v1/admin/backups/list", headers=support)
    assert backups.status_code == 403 and backups.json()["error"]["code"] == "SUPPORT_NOT_ALLOWED"
    # Nada se creó
    categories = (await client.get("/api/v1/inventory/categories", headers=owner)).json()
    assert "Refrescos" not in str(categories)

    # Sin canal en vivo de pedidos: se cierra antes de aceptar (4401)
    with TestClient(app) as sync_client:
        with pytest.raises(WebSocketDisconnect) as closed:
            with sync_client.websocket_connect(f"/api/v1/ws/orders?token={opened['access_token']}") as ws:
                ws.receive_json()
        assert closed.value.code == 4401


# -----------------------------------------------------------------------------
# CA-S7.3 — Retirar la concesión corta en la siguiente petición
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_revoking_the_permission_cuts_the_next_request(client: AsyncClient, db_session: AsyncSession):
    _, panel, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, _ = await _granted_store(client, "retira")
    _, opened = await _open(client, panel, tenant_id)
    support = _auth(opened["access_token"])
    assert (await client.get("/api/v1/inventory/products", headers=support)).status_code == 200

    detail = (await client.get(f"{P}/tenants/{tenant_id}", headers=panel)).json()
    assert [s["state"] for s in detail["support"]["support_sessions"]] == ["OPEN"]
    feed = (await client.get(f"{P}/feed", headers=panel)).json()
    assert any(a["kind"] == "SUPPORT_SESSION_OPEN" and a["tenant_id"] == str(tenant_id) for a in feed["attention"])

    await client.delete("/api/v1/support-access", headers=owner)
    cut = await client.get("/api/v1/inventory/products", headers=support)
    assert cut.status_code == 401
    assert cut.json()["error"]["code"] == "SUPPORT_ACCESS_ENDED"
    assert cut.json()["error"]["details"]["end_reason"] == "GRANT_ENDED"
    detail = (await client.get(f"{P}/tenants/{tenant_id}", headers=panel)).json()
    assert detail["support"]["support_sessions"] == []

    # El dueño lo ve en su historial, con lo que se revisó y cómo terminó
    sessions = (await client.get("/api/v1/support-access", headers=owner)).json()["sessions"]
    assert sessions[0]["active"] is False and sessions[0]["end_text"] == "Terminó tu permiso"
    assert sessions[0]["sections"] == ["Inventario"]


# -----------------------------------------------------------------------------
# CA-S7.4 — 30 min desde que se abre, extensible, nunca más que la concesión
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_session_expires_and_extends_within_the_permission(client: AsyncClient, db_session: AsyncSession):
    _, panel, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, _ = await _granted_store(client, "vence")
    started, opened = await _open(client, panel, tenant_id)
    session_id = started["session"]["id"]
    support = _auth(opened["access_token"])

    early = await client.post(f"{S}/extend", headers=support)
    assert early.status_code == 409 and "10 minutos" in early.json()["error"]["message"]

    # Faltan 5 min → «Seguir 30 min más» suma sobre lo que queda
    await _sql(db_session, "UPDATE support_sessions SET expires_at = now() + interval '5 minutes' WHERE id = :id", id=session_id)
    assert (await client.get(S, headers=support)).json()["can_extend"] is True
    extended = await client.post(f"{S}/extend", headers=support)
    assert extended.status_code == 200, extended.text
    new_until = datetime.fromisoformat(extended.json()["status"]["expires_at"])
    assert timedelta(minutes=34) < new_until - datetime.now(timezone.utc) <= timedelta(minutes=35)
    assert extended.json()["status"]["extensions"] == 1
    support = _auth(extended.json()["access_token"])
    activity = (await client.get("/api/v1/subscription/activity", headers=owner)).json()
    assert [a["action"] for a in activity[:2]] == ["SUPPORT_SESSION_EXTENDED", "SUPPORT_SESSION_STARTED"]
    assert "no podemos cambiar nada" in activity[1]["summary"] and activity[1]["reason"] == REASON

    # Nunca más allá del permiso del dueño
    await _sql(
        db_session,
        "UPDATE support_access_grants SET expires_at = now() + interval '12 minutes' WHERE tenant_id = :t AND revoked_at IS NULL",
        t=str(tenant_id),
    )
    await _sql(db_session, "UPDATE support_sessions SET expires_at = now() + interval '8 minutes' WHERE id = :id", id=session_id)
    capped = await client.post(f"{S}/extend", headers=support)
    assert capped.status_code == 200
    capped_until = datetime.fromisoformat(capped.json()["status"]["expires_at"])
    assert capped_until == datetime.fromisoformat(capped.json()["status"]["grant_expires_at"])
    assert capped.json()["status"]["can_extend"] is False
    support = _auth(capped.json()["access_token"])

    # Se acabó el tiempo
    await _sql(db_session, "UPDATE support_sessions SET expires_at = now() - interval '1 second' WHERE id = :id", id=session_id)
    expired = await client.get("/api/v1/inventory/products", headers=support)
    assert expired.status_code == 401 and expired.json()["error"]["details"]["end_reason"] == "EXPIRED"
    sessions = (await client.get("/api/v1/support-access", headers=owner)).json()["sessions"]
    assert sessions[0]["end_text"] == "Se acabó el tiempo"


@pytest.mark.asyncio
async def test_link_expires_unopened_and_reopening_keeps_the_clock(client: AsyncClient, db_session: AsyncSession):
    _, panel, _ = await _enrolled_session(client, db_session)
    _, tenant_id, _ = await _granted_store(client, "enlace")

    # Un enlace que nadie abrió en 10 min vence y la sesión no llega a empezar
    lost = (await client.post(f"{P}/tenants/{tenant_id}/support-sessions", json={"reason": REASON}, headers=panel)).json()
    await _sql(db_session, "UPDATE support_sessions SET link_expires_at = now() - interval '1 second' WHERE id = :id", id=lost["session"]["id"])
    late = await client.post(f"{S}/open", json={"code": lost["link_code"]})
    assert late.status_code == 410 and late.json()["error"]["code"] == "SUPPORT_LINK_EXPIRED"
    gone = await client.post(f"{P}/support-sessions/{lost['session']['id']}/link", headers=panel)
    assert gone.status_code == 401

    # «Abrir de nuevo» da otro enlace y no reinicia el reloj
    started, opened = await _open(client, panel, tenant_id)
    first_until = opened["status"]["expires_at"]
    relink = await client.post(f"{P}/support-sessions/{started['session']['id']}/link", headers=panel)
    assert relink.status_code == 200
    reopened = await client.post(f"{S}/open", json={"code": relink.json()["link_code"]})
    assert reopened.status_code == 200 and reopened.json()["status"]["expires_at"] == first_until


# -----------------------------------------------------------------------------
# Terminar: desde la pestaña, desde el panel, al salir del panel
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_ending_from_the_tab_the_panel_or_signing_out(client: AsyncClient, db_session: AsyncSession):
    _, panel, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, _ = await _granted_store(client, "termina", hours=24)

    _, opened = await _open(client, panel, tenant_id)
    support = _auth(opened["access_token"])
    await client.get("/api/v1/sales", headers=support)
    assert (await client.post(f"{S}/end", headers=support)).status_code == 204
    after = await client.get("/api/v1/inventory/products", headers=support)
    assert after.status_code == 401 and after.json()["error"]["details"]["end_reason"] == "OPERATOR"
    assert (await client.post(f"{S}/end", headers=support)).status_code == 204  # dos veces no falla

    started, opened = await _open(client, panel, tenant_id)
    ended = await client.post(f"{P}/support-sessions/{started['session']['id']}/end", headers=panel)
    assert ended.status_code == 200 and ended.json()["end_reason"] == "OPERATOR"
    assert (await client.get(S, headers=_auth(opened["access_token"]))).status_code == 401

    _, opened = await _open(client, panel, tenant_id)
    assert (await client.post(f"{P}/auth/logout", headers=panel)).status_code == 204
    out = await client.get("/api/v1/inventory/products", headers=_auth(opened["access_token"]))
    assert out.status_code == 401 and out.json()["error"]["details"]["end_reason"] == "SIGNED_OUT"

    owner_view = (await client.get("/api/v1/support-access", headers=owner)).json()["sessions"]
    assert [s["end_text"] for s in owner_view] == ["Soporte salió del panel", "Soporte la terminó", "Soporte la terminó"]
    assert owner_view[-1]["sections"] == ["Ventas"] and owner_view[-1]["by"] == "Soporte Nexus · Operadora de Prueba"
    audit = (await client.get(f"{P}/audit", params={"tenant_id": str(tenant_id)}, headers=panel)).json()["items"]
    ends = [e for e in audit if e["action"] == "SUPPORT_SESSION_ENDED"]
    assert len(ends) == 3 and ends[-1]["details"]["secciones"] == ["Ventas"]
    assert "abrió una sesión de soporte" in next(e for e in audit if e["action"] == "SUPPORT_SESSION_STARTED")["summary"]


@pytest.mark.asyncio
async def test_deactivated_operator_loses_the_session(client: AsyncClient, db_session: AsyncSession):
    op, panel, _ = await _enrolled_session(client, db_session)
    _, tenant_id, _ = await _granted_store(client, "baja")
    _, opened = await _open(client, panel, tenant_id)
    await _sql(db_session, "UPDATE platform_operators SET is_active = false WHERE email = :e", e=op.email)
    cut = await client.get("/api/v1/inventory/products", headers=_auth(opened["access_token"]))
    assert cut.status_code == 401 and cut.json()["error"]["details"]["end_reason"] == "OPERATOR_INACTIVE"


@pytest.mark.asyncio
async def test_owner_preview_of_a_support_session(client: AsyncClient, db_session: AsyncSession):
    _, panel, _ = await _enrolled_session(client, db_session)
    _, tenant_id, _ = await _granted_store(client, "vistaprevia")
    preview = await client.post(
        f"{P}/tenants/{tenant_id}/preview", json={"action": "SUPPORT_SESSION_STARTED", "reason": REASON}, headers=panel,
    )
    assert preview.status_code == 200
    assert "sólo para consultar" in preview.json()["summary"] and preview.json()["reason"] == REASON


@pytest.mark.asyncio
async def test_a_new_permission_keeps_the_session_going(client: AsyncClient, db_session: AsyncSession):
    """Decisión de Eduardo (Sep 30): ampliar el permiso con soporte dentro no lo saca."""
    _, panel, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, _ = await _granted_store(client, "amplia", hours=1)
    started, opened = await _open(client, panel, tenant_id)
    support = _auth(opened["access_token"])

    widened = await client.post("/api/v1/support-access", json={"hours": 24}, headers=owner)
    assert widened.status_code == 200
    still = await client.get("/api/v1/inventory/products", headers=support)
    assert still.status_code == 200, still.text
    status = (await client.get(S, headers=support)).json()
    assert status["expires_at"] == opened["status"]["expires_at"]  # el reloj no cambia
    assert datetime.fromisoformat(status["grant_expires_at"]) - datetime.now(timezone.utc) > timedelta(hours=23)
    detail = (await client.get(f"{P}/tenants/{tenant_id}", headers=panel)).json()
    assert [x["id"] for x in detail["support"]["support_sessions"]] == [started["session"]["id"]]

    # Si el nuevo permiso es más corto que lo que le queda a la sesión, la sesión termina con él
    await _sql(db_session, "UPDATE support_sessions SET expires_at = now() + interval '90 minutes' WHERE id = :id",
               id=started["session"]["id"])
    await _sql(db_session, "UPDATE support_access_grants SET expires_at = now() + interval '2 hours' "
               "WHERE tenant_id = :t AND revoked_at IS NULL", t=str(tenant_id))
    shorter = await client.post("/api/v1/support-access", json={"hours": 1}, headers=owner)
    assert shorter.status_code == 200
    status = (await client.get(S, headers=support)).json()
    assert status["expires_at"] == status["grant_expires_at"]  # 90 min recortados a la hora del permiso nuevo
    assert datetime.fromisoformat(status["expires_at"]) - datetime.now(timezone.utc) <= timedelta(hours=1)

    # Retirar sí corta
    await client.delete("/api/v1/support-access", headers=owner)
    assert (await client.get("/api/v1/inventory/products", headers=support)).status_code == 401
