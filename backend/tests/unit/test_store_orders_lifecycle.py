# Importación de asyncio para leer la cola del hub
import asyncio
# Importación del módulo decimal para cálculos monetarios exactos
from decimal import Decimal
# Importación del módulo uuid para generar identificadores únicos
import uuid

# Importación de pytest para pruebas asíncronas
import pytest
# Importación de AsyncClient de httpx para peticiones HTTP
from httpx import AsyncClient
# Importación del TestClient síncrono para el handshake del WebSocket
from starlette.testclient import TestClient

from app.main import app
from app.modules.whatsapp_catalog.api.rate_limit import public_order_limiter
from app.modules.whatsapp_catalog.services.order_event_hub import order_event_hub


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

async def _store_with_product(client: AsyncClient, prefix: str, price: float = 28.50, stock: int = 30):
    """Registra comercio, configura WhatsApp y crea un producto. Devuelve (slug, headers, product_id, tenant_id)."""
    suffix = uuid.uuid4().hex[:6]
    slug = f"{prefix}-{suffix}"
    reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda {prefix} {suffix}",
            "slug": slug,
            "full_name": f"Dueño {prefix}",
            "email": f"{prefix}_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg.status_code == 201, reg.text
    headers = {"Authorization": f"Bearer {reg.json()['access_token']}"}
    tenant_id = uuid.UUID(reg.json()["tenant"]["id"])
    await client.put(
        "/api/v1/catalog-settings",
        json={"whatsapp_number": "5511112222", "delivery_fee_mxn": 15.00},
        headers=headers,
    )
    prod = await client.post(
        "/api/v1/inventory/products",
        json={"name": f"Leche {suffix}", "sku": f"LCH-{suffix}", "price_mxn": price, "cost_mxn": 20.0, "initial_stock": stock},
        headers=headers,
    )
    assert prod.status_code == 201, prod.text
    return slug, headers, prod.json()["id"], tenant_id


def _payload(product_id: str, name: str = "Ana López", qty: int = 2):
    return {
        "customer_name": name,
        "customer_phone": "5533334444",
        "delivery_method": "PICKUP",
        "payment_method": "CASH",
        "cash_tendered_mxn": 100.00,
        "items": [{"product_id": product_id, "quantity": qty}],
    }


async def _checkout(client: AsyncClient, headers: dict, product_id: str, qty: int = 1) -> str:
    """Venta real en el POS (lo que hace "Cobrar en caja"); devuelve el id de la venta."""
    wh = (await client.get("/api/v1/inventory/warehouses", headers=headers)).json()[0]["id"]
    resp = await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": wh,
            "items": [{"product_id": product_id, "quantity": qty, "unit_price_mxn": 28.50}],
            "payments": [{"payment_method": "CASH_MXN", "amount_paid_mxn": 28.50 * qty}],
        },
        headers=headers,
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _submit(client: AsyncClient, slug: str, product_id: str, **kw) -> dict:
    resp = await client.post(f"/api/v1/public/catalog/{slug}/orders", json=_payload(product_id, **kw))
    assert resp.status_code == 201, resp.text
    return resp.json()


# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_new_order_is_listed_with_server_badge_and_opening_marks_seen(client: AsyncClient):
    """Fase 1: la lista y el badge salen del servidor; abrir el pedido lo marca visto."""
    slug, headers, product_id, _ = await _store_with_product(client, "lista")
    order = await _submit(client, slug, product_id)

    listed = await client.get("/api/v1/catalog-orders", headers=headers)
    assert listed.status_code == 200, listed.text
    body = listed.json()
    assert body["new_count"] == 1
    assert body["active_count"] == 1
    assert body["items"][0]["folio"] == order["folio"]
    assert body["items"][0]["status"] == "NEW"
    assert body["items"][0]["seen_at"] is None

    detail = await client.get(f"/api/v1/catalog-orders/{order['folio']}", headers=headers)
    assert detail.status_code == 200
    assert detail.json()["seen_at"] is not None
    assert detail.json()["seen_by_name"] == "Dueño lista"

    after = await client.get("/api/v1/catalog-orders", headers=headers)
    assert after.json()["new_count"] == 0  # visto, sigue activo
    assert after.json()["active_count"] == 1


@pytest.mark.asyncio
async def test_status_transitions_cancel_reason_and_reopen(client: AsyncClient):
    """NEW → READY → DELIVERED; cancelar exige motivo; reabrir vuelve a NEW."""
    slug, headers, product_id, _ = await _store_with_product(client, "estados")
    folio = (await _submit(client, slug, product_id))["folio"]
    url = f"/api/v1/catalog-orders/{folio}/status"

    ready = await client.patch(url, json={"status": "READY"}, headers=headers)
    assert ready.status_code == 200, ready.text
    assert ready.json()["status"] == "READY"
    assert ready.json()["attended_by_name"] == "Dueño estados"

    no_reason = await client.patch(url, json={"status": "CANCELLED"}, headers=headers)
    assert no_reason.status_code == 422

    cancelled = await client.patch(url, json={"status": "CANCELLED", "cancel_reason": "CUSTOMER_CANCELLED"}, headers=headers)
    assert cancelled.status_code == 200
    assert cancelled.json()["cancel_reason"] == "CUSTOMER_CANCELLED"

    # Cancelado ya no está en activos, sí en historial
    active = await client.get("/api/v1/catalog-orders?scope=active", headers=headers)
    assert all(o["folio"] != folio for o in active.json()["items"])
    history = await client.get("/api/v1/catalog-orders?scope=history", headers=headers)
    assert any(o["folio"] == folio for o in history.json()["items"])

    # Desde cancelado sólo se puede reabrir
    bad = await client.patch(url, json={"status": "READY"}, headers=headers)
    assert bad.status_code == 400
    reopened = await client.patch(url, json={"status": "NEW"}, headers=headers)
    assert reopened.status_code == 200
    assert reopened.json()["status"] == "NEW"
    assert reopened.json()["cancel_reason"] is None

    # Entregar sin venta ligada no existe: entregar es vender.
    no_sale = await client.patch(url, json={"status": "DELIVERED"}, headers=headers)
    assert no_sale.status_code == 422
    assert "cobrarlo en caja" in no_sale.json()["detail"]
    sale_id = await _checkout(client, headers, product_id)
    delivered = await client.patch(url, json={"status": "DELIVERED", "sale_id": sale_id}, headers=headers)
    assert delivered.status_code == 200

    # El ticket público refleja el estado sin sesión (con la clave del enlace)
    key = (await client.get(f"/api/v1/catalog-orders/{folio}", headers=headers)).json()["access_key"]
    public = await client.get(f"/api/v1/public/catalog/{slug}/orders/{folio}?k={key}")
    assert public.status_code == 200
    assert public.json()["status"] == "DELIVERED"


@pytest.mark.asyncio
async def test_optimistic_concurrency_returns_409(client: AsyncClient):
    """Dos empleados sobre el mismo pedido: el segundo cambio con versión vieja recibe 409."""
    slug, headers, product_id, _ = await _store_with_product(client, "conc")
    folio = (await _submit(client, slug, product_id))["folio"]
    url = f"/api/v1/catalog-orders/{folio}/status"

    first = await client.get(f"/api/v1/catalog-orders/{folio}", headers=headers)
    version = first.json()["updated_at"]

    ok = await client.patch(url, json={"status": "READY", "expected_updated_at": version}, headers=headers)
    assert ok.status_code == 200, ok.text

    stale = await client.patch(url, json={"status": "CANCELLED", "cancel_reason": "OTHER", "expected_updated_at": version}, headers=headers)
    assert stale.status_code == 409
    assert "Alguien más" in stale.json()["detail"]

    fresh = await client.patch(
        url,
        json={"status": "CANCELLED", "cancel_reason": "OTHER", "expected_updated_at": ok.json()["updated_at"]},
        headers=headers,
    )
    assert fresh.status_code == 200


@pytest.mark.asyncio
async def test_edit_keeps_revision_recomputes_totals_and_marks_public_ticket(client: AsyncClient):
    """Fase 2: editar conserva la versión anterior, recalcula y el ticket público lo anuncia."""
    slug, headers, product_id, _ = await _store_with_product(client, "edicion")
    order = await _submit(client, slug, product_id)  # 2 × 28.50 = 57.00, recoger, paga con 100
    folio = order["folio"]
    assert Decimal(str(order["change_mxn"])) == Decimal("43.00")

    edited = await client.put(
        f"/api/v1/catalog-orders/{folio}",
        json={
            "items": [{"product_id": product_id, "quantity": 3, "notes": "bien fría"}],
            "delivery_method": "DELIVERY",
            "delivery_address": "Calle Luna 5, Centro",
            "order_notes": "Cambió por chat",
            "expected_updated_at": order["updated_at"],
        },
        headers=headers,
    )
    assert edited.status_code == 200, edited.text
    body = edited.json()
    assert Decimal(str(body["subtotal_mxn"])) == Decimal("85.50")
    assert Decimal(str(body["delivery_fee_mxn"])) == Decimal("15.00")
    assert Decimal(str(body["total_mxn"])) == Decimal("100.50")
    assert body["change_mxn"] is None  # ya no alcanza con los $100 — no se rechaza, se recalcula
    assert body["delivery_address"] == "Calle Luna 5, Centro"
    assert body["items"][0]["notes"] == "bien fría"
    assert body["store_edited_at"] is not None
    assert body["edited_by_name"] == "Dueño edicion"
    assert len(body["revisions"]) == 1
    previous = body["revisions"][0]
    assert Decimal(str(previous["total_mxn"])) == Decimal("57.00")
    assert previous["delivery_method"] == "PICKUP"
    assert Decimal(str(previous["items"][0]["quantity"])) == Decimal("2")

    public = await client.get(f"/api/v1/public/catalog/{slug}/orders/{folio}?k={order['access_key']}")
    assert public.json()["store_edited_at"] is not None
    assert Decimal(str(public.json()["total_mxn"])) == Decimal("100.50")

    # Un pedido cerrado ya no se edita
    await client.patch(
        f"/api/v1/catalog-orders/{folio}/status",
        json={"status": "CANCELLED", "cancel_reason": "OTHER"},
        headers=headers,
    )
    blocked = await client.put(
        f"/api/v1/catalog-orders/{folio}",
        json={"items": [{"product_id": product_id, "quantity": 1}], "delivery_method": "PICKUP"},
        headers=headers,
    )
    assert blocked.status_code == 400


@pytest.mark.asyncio
async def test_link_sale_marks_delivered_and_blocks_reopen(client: AsyncClient):
    """Fase 3: "Cobrar en caja" liga la venta; un pedido cobrado no se reabre desde aquí."""
    slug, headers, product_id, _ = await _store_with_product(client, "cobro")
    folio = (await _submit(client, slug, product_id))["folio"]
    sale_id = await _checkout(client, headers, product_id)

    delivered = await client.patch(
        f"/api/v1/catalog-orders/{folio}/status",
        json={"status": "DELIVERED", "sale_id": sale_id},
        headers=headers,
    )
    assert delivered.status_code == 200
    assert delivered.json()["status"] == "DELIVERED"
    assert delivered.json()["sale_id"] == sale_id

    # Cobrado en caja: no se reabre desde aquí (se devuelve desde la venta)
    reopen = await client.patch(
        f"/api/v1/catalog-orders/{folio}/status", json={"status": "NEW"}, headers=headers
    )
    assert reopen.status_code == 400


@pytest.mark.asyncio
async def test_duplicate_detection_flags_second_identical_order(client: AsyncClient):
    """El cliente tocó enviar dos veces: el segundo se marca, nunca se fusiona."""
    slug, headers, product_id, _ = await _store_with_product(client, "dup")
    first = await _submit(client, slug, product_id)
    second = await _submit(client, slug, product_id)
    assert first["folio"] != second["folio"]

    listed = await client.get("/api/v1/catalog-orders", headers=headers)
    by_folio = {o["folio"]: o for o in listed.json()["items"]}
    assert by_folio[second["folio"]]["possible_duplicate_of"] == first["folio"]
    assert by_folio[first["folio"]]["possible_duplicate_of"] is None
    assert listed.json()["new_count"] == 2


@pytest.mark.asyncio
async def test_submit_publishes_order_new_event_to_tenant_hub(client: AsyncClient):
    """El registro público publica `order.new` sólo al comercio dueño, después del commit."""
    slug, headers, product_id, tenant_id = await _store_with_product(client, "evento")
    queue = order_event_hub.subscribe(tenant_id)
    other_queue = order_event_hub.subscribe(uuid.uuid4())
    try:
        order = await _submit(client, slug, product_id)
        event = await asyncio.wait_for(queue.get(), timeout=2)
        assert event["type"] == "order.new"
        assert event["order"]["folio"] == order["folio"]
        assert event["order"]["status"] == "NEW"
        assert other_queue.empty()

        await client.patch(f"/api/v1/catalog-orders/{order['folio']}/status", json={"status": "READY"}, headers=headers)
        updated = await asyncio.wait_for(queue.get(), timeout=2)
        assert updated["type"] == "order.updated"
        assert updated["order"]["status"] == "READY"
    finally:
        order_event_hub.unsubscribe(tenant_id, queue)
        order_event_hub.unsubscribe(uuid.uuid4(), other_queue)


@pytest.mark.asyncio
async def test_public_ticket_rate_limit_returns_429(client: AsyncClient):
    """La página del ticket se refresca sola; más de 60 lecturas/min por IP → 429."""
    from app.modules.whatsapp_catalog.api.rate_limit import public_ticket_limiter
    slug, headers, product_id, _ = await _store_with_product(client, "ticketlim")
    order = await _submit(client, slug, product_id)
    url = f"/api/v1/public/catalog/{slug}/orders/{order['folio']}?k={order['access_key']}"
    public_ticket_limiter.reset()
    try:
        for _ in range(60):
            assert (await client.get(url)).status_code == 200
        assert (await client.get(url)).status_code == 429
    finally:
        public_ticket_limiter.reset()


@pytest.mark.asyncio
async def test_public_order_rate_limit_returns_429(client: AsyncClient):
    """Más de 10 pedidos por minuto desde la misma IP a la misma tienda → 429."""
    slug, headers, product_id, _ = await _store_with_product(client, "spam")
    public_order_limiter.reset()
    try:
        for _ in range(10):
            resp = await client.post(f"/api/v1/public/catalog/{slug}/orders", json=_payload(product_id))
            assert resp.status_code == 201, resp.text
        blocked = await client.post(f"/api/v1/public/catalog/{slug}/orders", json=_payload(product_id))
        assert blocked.status_code == 429
        # Otra tienda no se ve afectada por el spam a la primera
        slug2, _, product2, _ = await _store_with_product(client, "spam2")
        ok = await client.post(f"/api/v1/public/catalog/{slug2}/orders", json=_payload(product2))
        assert ok.status_code == 201
    finally:
        public_order_limiter.reset()


def test_orders_websocket_rejects_bad_token_and_greets_valid_user():
    """Handshake del WebSocket: token inválido cierra con 4401; válido recibe `hello`."""
    with TestClient(app) as tc:
        suffix = uuid.uuid4().hex[:6]
        reg = tc.post(
            "/api/v1/auth/register",
            json={
                "store_name": f"WS {suffix}",
                "slug": f"ws-{suffix}",
                "full_name": "Dueño WS",
                "email": f"ws_{suffix}@tienda.mx",
                "password": "password123",
            },
        )
        assert reg.status_code == 201, reg.text
        token = reg.json()["access_token"]
        tenant_id = reg.json()["tenant"]["id"]

        with pytest.raises(Exception):
            with tc.websocket_connect("/api/v1/ws/orders?token=invalido") as ws:
                ws.receive_json()

        with tc.websocket_connect(f"/api/v1/ws/orders?token={token}") as ws:
            hello = ws.receive_json()
            assert hello == {"type": "hello", "tenant_id": tenant_id}
