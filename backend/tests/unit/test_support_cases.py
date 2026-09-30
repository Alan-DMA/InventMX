"""
Apartado de Soporte estilo Steam — etapa 2a, backend (P23–P25). Criterios:
CA-S2.7 ayuda antes del formulario y el caso llega al panel con tema y campos ·
CA-S2.8 sin sesión se abre un caso y la respuesta llega por correo, con tope ·
CA-S2.9 cada quien ve sus casos y el dueño todos · temas editables sin publicar.
"""
import uuid

import pytest
from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.email.sender import console_outbox
from test_platform_admin import P, _enrolled_session, _register_store

S = "/api/v1/support"


@pytest.fixture(autouse=True)
def _clean_outbox():
    console_outbox.clear()
    yield
    console_outbox.clear()


def _auth(body: dict) -> dict:
    return {"Authorization": f"Bearer {body['access_token']}"}


async def _cashier(client: AsyncClient, owner: dict) -> tuple[dict, str]:
    roles = (await client.get("/api/v1/roles", headers=owner)).json()
    role = next(r for r in roles if r["name"] == "CASHIER")
    email = f"caj_{uuid.uuid4().hex[:6]}@tienda.mx"
    created = await client.post(
        "/api/v1/users",
        json={"email": email, "password": "empleado123", "full_name": "Cajera Lupita", "role_id": role["id"]},
        headers=owner,
    )
    assert created.status_code == 201, created.text
    login = await client.post("/api/v1/auth/login", json={"email": email, "password": "empleado123"})
    return _auth(login.json()), email


def _ip() -> dict:
    return {"X-Forwarded-For": f"10.{uuid.uuid4().int % 250}.{uuid.uuid4().int % 250}.{uuid.uuid4().int % 250}"}


BROKEN = {
    "topic_key": "something_broken",
    "answers": {"module": "Caja", "when": "Hoy en la mañana"},
    "description": "Al cerrar el turno la app se queda cargando y no avanza.",
}


# -----------------------------------------------------------------------------
# Temas servidos por el servidor, según el rol
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_topics_come_from_the_server_by_role(client: AsyncClient):
    owner, _, _ = await _register_store(client, "temas")
    cashier, _ = await _cashier(client, owner)

    owner_keys = [t["key"] for t in (await client.get(f"{S}/topics", headers=owner)).json()]
    cashier_keys = [t["key"] for t in (await client.get(f"{S}/topics", headers=cashier)).json()]
    assert {"subscription", "my_data", "something_broken", "other"} <= set(owner_keys)
    assert "subscription" not in cashier_keys and "my_data" not in cashier_keys
    assert "cannot_login" not in owner_keys  # ése es el de sin sesión

    broken = next(t for t in (await client.get(f"{S}/topics", headers=owner)).json() if t["key"] == "something_broken")
    assert broken["body"].startswith("Antes de escribirnos")  # la ayuda va antes del formulario
    assert [f["key"] for f in broken["form_fields"]] == ["module", "when", "steps"]

    public = (await client.get(f"{S}/public/topics")).json()
    assert [t["key"] for t in public] == ["cannot_login"]


# -----------------------------------------------------------------------------
# CA-S2.7 / CA-S2.9 — el caso, su formulario y quién lo ve
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_case_form_is_validated_against_the_topic(client: AsyncClient):
    owner, _, _ = await _register_store(client, "formulario")
    cashier, _ = await _cashier(client, owner)

    missing = await client.post(f"{S}/cases", json={**BROKEN, "answers": {}}, headers=owner)
    assert missing.status_code == 422 and "En qué parte" in missing.json()["detail"]
    bad_option = await client.post(f"{S}/cases", json={**BROKEN, "answers": {"module": "Cocina"}}, headers=owner)
    assert bad_option.status_code == 422
    short = await client.post(f"{S}/cases", json={**BROKEN, "description": "falla"}, headers=owner)
    assert short.status_code == 422
    owner_only = await client.post(
        f"{S}/cases",
        json={"topic_key": "my_data", "answers": {"request": "Una copia de mis datos"},
              "description": "Quiero una copia de todo lo de la tienda."},
        headers=cashier,
    )
    assert owner_only.status_code == 422

    created = await client.post(f"{S}/cases", json={**BROKEN, "answers": {**BROKEN["answers"], "extra": "x"}}, headers=owner)
    assert created.status_code == 201, created.text
    case = created.json()
    assert case["number"] >= 1001 and case["status"] == "WAITING_SUPPORT"
    assert case["topic_title"] == "Algo no funciona"
    assert case["answers"] == [
        {"key": "module", "label": "¿En qué parte de la app?", "value": "Caja"},
        {"key": "when", "label": "¿Cuándo pasó?", "value": "Hoy en la mañana"},
    ]
    assert case["messages"][0]["body"] == BROKEN["description"]
    assert case["messages"][0]["author_kind"] == "REQUESTER"


@pytest.mark.asyncio
async def test_each_one_sees_their_cases_and_the_owner_sees_all(client: AsyncClient):
    owner, _, _ = await _register_store(client, "visibles")
    cashier, _ = await _cashier(client, owner)
    stranger, _, _ = await _register_store(client, "ajena")

    mine = (await client.post(f"{S}/cases", json=BROKEN, headers=cashier)).json()
    boss = (await client.post(
        f"{S}/cases", json={"topic_key": "other", "description": "¿Puedo tener dos tiendas en una cuenta?"}, headers=owner,
    )).json()

    cashier_list = (await client.get(f"{S}/cases", headers=cashier)).json()
    assert [c["id"] for c in cashier_list] == [mine["id"]] and cashier_list[0]["is_mine"] is True
    owner_list = {c["id"]: c for c in (await client.get(f"{S}/cases", headers=owner)).json()}
    assert set(owner_list) == {mine["id"], boss["id"]}
    assert owner_list[mine["id"]]["author_name"] == "Cajera Lupita" and owner_list[mine["id"]]["is_mine"] is False

    assert (await client.get(f"{S}/cases/{boss['id']}", headers=cashier)).status_code == 404
    assert (await client.get(f"{S}/cases/{mine['id']}", headers=stranger)).status_code == 404
    assert (await client.get(f"{S}/cases", headers=stranger)).json() == []


# -----------------------------------------------------------------------------
# Del tendero al panel y de vuelta
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_case_round_trip_between_store_and_panel(client: AsyncClient, db_session: AsyncSession):
    _, desk, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, _ = await _register_store(client, "idavuelta")
    cashier, cashier_email = await _cashier(client, owner)
    case = (await client.post(f"{S}/cases", json=BROKEN, headers=cashier)).json()

    # En el panel: espera respuesta, con tema y campos
    feed = (await client.get(f"{P}/feed", headers=desk)).json()
    waiting = [a for a in feed["attention"] if a["kind"] == "CASE_WAITING" and a["ref_id"] == case["id"]]
    assert waiting and waiting[0]["tenant_id"] == str(tenant_id)
    assert any(e["kind"] == "CASE" and f"Caso {case['number']}" in e["summary"] for e in feed["events"])
    listed = (await client.get(f"{P}/cases", params={"q": str(case["number"])}, headers=desk)).json()
    assert listed["total"] == 1 and listed["items"][0]["tenant_name"].startswith("Abarrotes idavuelta")
    detail = (await client.get(f"{P}/cases/{case['id']}", headers=desk)).json()
    assert detail["answers"][0]["value"] == "Caja" and detail["messages"][0]["author_name"] == "Cajera Lupita"

    reply = "Ya lo vimos: fue una falla del cierre de turno. Actualiza la app y vuelve a intentarlo."
    answered = await client.post(f"{P}/cases/{case['id']}/messages", json={"body": reply}, headers=desk)
    assert answered.status_code == 200, answered.text
    assert answered.json()["status"] == "ANSWERED"
    [mail] = [m for m in console_outbox if m.to_email == cashier_email]
    assert reply in mail.text and "☰ · Soporte" in mail.text

    # La insignia es de quien escribió, no del dueño
    assert (await client.get(f"{S}/cases/unread", headers=cashier)).json() == {"unread": 1}
    assert (await client.get(f"{S}/cases/unread", headers=owner)).json() == {"unread": 0}
    seen = (await client.get(f"{S}/cases/{case['id']}", headers=cashier)).json()
    assert seen["messages"][-1]["author_name"] == "Soporte Nexus · Operadora de Prueba"
    assert (await client.get(f"{S}/cases/unread", headers=cashier)).json() == {"unread": 0}

    again = (await client.post(f"{S}/cases/{case['id']}/messages", json={"body": "Ya actualicé y sigue igual."},
                               headers=cashier)).json()
    assert again["status"] == "WAITING_SUPPORT" and len(again["messages"]) == 3
    resolved = (await client.post(f"{S}/cases/{case['id']}/resolve", headers=cashier)).json()
    assert resolved["status"] == "RESOLVED"
    reopened = (await client.post(f"{S}/cases/{case['id']}/messages", json={"body": "Volvió a pasar hoy."},
                                  headers=cashier)).json()
    assert reopened["status"] == "WAITING_SUPPORT"

    audit = (await client.get(f"{P}/audit", params={"action": "CASE_REPLIED"}, headers=desk)).json()["items"]
    assert any(e["target_id"] == case["id"] for e in audit)


@pytest.mark.asyncio
async def test_a_store_suspended_for_abuse_can_still_write_to_support(client: AsyncClient, db_session: AsyncSession):
    _, desk, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, _ = await _register_store(client, "suspsoporte")
    await client.post(f"{P}/tenants/{tenant_id}/suspension",
                      json={"reason": "Prueba: suspendida para ver que aún escribe a soporte."}, headers=desk)

    assert (await client.get("/api/v1/inventory/products", headers=owner)).status_code == 402
    assert (await client.get(f"{S}/topics", headers=owner)).status_code == 200
    created = await client.post(
        f"{S}/cases",
        json={"topic_key": "account_suspended", "description": "No entiendo por qué suspendieron mi tienda."},
        headers=owner,
    )
    assert created.status_code == 201, created.text
    # El acceso de soporte (otra ruta que empieza igual) sigue bloqueado
    assert (await client.get("/api/v1/support-access", headers=owner)).status_code == 402


# -----------------------------------------------------------------------------
# CA-S2.8 — Sin sesión
# -----------------------------------------------------------------------------

def _public(account_email: str, contact: str) -> dict:
    return {
        "topic_key": "cannot_login",
        "answers": {"problem": "Perdí acceso a mi correo"},
        "description": "Cambié de celular y ya no tengo el correo con el que me registré.",
        "account_email": account_email,
        "store_name": "Abarrotes Doña Chuy",
        "contact_email": contact,
        "contact_name": "Chuy",
    }


@pytest.mark.asyncio
async def test_public_form_opens_a_case_that_only_the_panel_sees(client: AsyncClient, db_session: AsyncSession):
    _, desk, _ = await _enrolled_session(client, db_session)
    owner, tenant_id, account = await _register_store(client, "sinsesion")
    contact = f"chuy_{uuid.uuid4().hex[:6]}@otro.mx"
    ip = _ip()

    known = await client.post(f"{S}/public/cases", json=_public(account, contact), headers=ip)
    unknown = await client.post(f"{S}/public/cases", json=_public("nadie_zz@tienda.mx", f"x{contact}"), headers=_ip())
    assert known.status_code == unknown.status_code == 202
    assert known.json() == unknown.json()  # no delata si el correo tiene cuenta
    [receipt] = [m for m in console_outbox if m.to_email == contact]
    number = int(receipt.subject.split()[-1])

    # La tienda no lo ve (quien escribe sin sesión podría no ser su dueño)
    assert (await client.get(f"{S}/cases", headers=owner)).json() == []
    page = (await client.get(f"{P}/cases", params={"q": str(number)}, headers=desk)).json()
    case = page["items"][0]
    assert case["channel"] == "PUBLIC" and case["tenant_id"] is None
    assert case["suggested_tenant_id"] == str(tenant_id) and case["claimed_store_name"] == "Abarrotes Doña Chuy"

    console_outbox.clear()
    await client.post(
        f"{P}/cases/{case['id']}/messages",
        json={"body": "Para validar que eres la dueña, dinos cuándo te registraste y quiénes trabajan contigo.",
              "resolve": False},
        headers=desk,
    )
    [answer] = [m for m in console_outbox if m.to_email == contact]
    assert f"caso {number}" in answer.text and "No puedo entrar a mi cuenta" in answer.text


@pytest.mark.asyncio
async def test_public_form_has_a_daily_cap_and_a_bot_trap(client: AsyncClient, db_session: AsyncSession):
    _, desk, _ = await _enrolled_session(client, db_session)
    contact = f"tope_{uuid.uuid4().hex[:6]}@otro.mx"

    bot = await client.post(
        f"{S}/public/cases", json={**_public("a@b.mx", contact), "website": "http://spam"}, headers=_ip(),
    )
    assert bot.status_code == 202 and console_outbox == []

    for _ in range(4):
        resp = await client.post(f"{S}/public/cases", json=_public("a@b.mx", contact), headers=_ip())
        assert resp.status_code == 202
    assert len([m for m in console_outbox if m.to_email == contact]) == 3
    page = (await client.get(f"{P}/cases", params={"q": contact}, headers=desk)).json()
    assert page["total"] == 3

    # El tope también es por IP, aunque cambie el correo
    ip = _ip()
    for i in range(4):
        await client.post(f"{S}/public/cases", json=_public("a@b.mx", f"ip{i}_{contact}"), headers=ip)
    assert len([m for m in console_outbox if m.to_email.endswith(contact) and m.to_email.startswith("ip")]) == 3


# -----------------------------------------------------------------------------
# Temas editables desde el panel (sin publicar la app)
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_help_topics_are_edited_from_the_panel(client: AsyncClient, db_session: AsyncSession):
    _, desk, _ = await _enrolled_session(client, db_session)
    owner, _, _ = await _register_store(client, "editable")
    key = f"qa_{uuid.uuid4().hex[:6]}"
    body = {
        "title": "Impresora de tickets",
        "summary": "La impresora no imprime.",
        "body": "Revisa que esté encendida y vinculada por Bluetooth.",
        "actions": [],
        "form_fields": [{"key": "model", "label": "¿Qué impresora?", "type": "select", "required": True,
                         "options": ["Térmica 58 mm", "Térmica 80 mm"]}],
        "audience": "ALL",
        "sort_order": 60,
        "is_active": True,
        "reason": "Varios tenderos preguntan por la impresora.",
    }
    try:
        bad = await client.put(
            f"{P}/help-topics/{key}",
            json={**body, "form_fields": [{"key": "model", "label": "x", "type": "select", "options": ["uno"]}]},
            headers=desk,
        )
        assert bad.status_code == 422
        assert (await client.put(f"{P}/help-topics/{key}", json=body, headers=desk)).status_code == 200

        topics = {t["key"]: t for t in (await client.get(f"{S}/topics", headers=owner)).json()}
        assert topics[key]["title"] == "Impresora de tickets"
        case = (await client.post(
            f"{S}/cases",
            json={"topic_key": key, "answers": {"model": "Térmica 58 mm"}, "description": "No imprime nada desde ayer."},
            headers=owner,
        )).json()

        # Cambiar la etiqueta no reescribe los casos viejos; desactivarlo lo quita de la app
        renamed = {**body, "is_active": False,
                   "form_fields": [{**body["form_fields"][0], "label": "Modelo de impresora"}]}
        assert (await client.put(f"{P}/help-topics/{key}", json=renamed, headers=desk)).status_code == 200
        assert key not in [t["key"] for t in (await client.get(f"{S}/topics", headers=owner)).json()]
        old = (await client.get(f"{S}/cases/{case['id']}", headers=owner)).json()
        assert old["answers"][0]["label"] == "¿Qué impresora?"

        audit = (await client.get(f"{P}/audit", params={"action": "HELP_TOPIC_UPDATED"}, headers=desk)).json()["items"]
        assert any(e["target_id"] == key and e["reason"] == body["reason"] for e in audit)
    finally:
        await db_session.rollback()
        await db_session.execute(text("DELETE FROM help_topics WHERE key = :k"), {"k": key})
        await db_session.commit()
