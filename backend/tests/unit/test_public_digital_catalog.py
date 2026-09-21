# Importación del módulo decimal para cálculos monetarios exactos
from decimal import Decimal
# Importación del módulo uuid para generar identificadores únicos
import uuid
# Importación de pytest para pruebas asíncronas
import pytest
# Importación de AsyncClient de httpx para peticiones HTTP
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_public_catalog_retrieval_by_slug(client: AsyncClient):
    """
    Test 1: Consulta pública de catálogo digital por slug de tienda sin token JWT (RF-23).
    """
    # 1. Registrar comercio
    suffix = uuid.uuid4().hex[:6]
    slug = f"abarrotes-pepe-{suffix}"
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Don Pepe {suffix}",
            "slug": slug,
            "full_name": "Don Pepe",
            "email": f"pepe_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Crear 2 productos en el inventario del comercio
    p1_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Coca-Cola 600ml",
            "sku": f"COC-600-{suffix}",
            "price_mxn": 18.50,
            "cost_mxn": 14.00,
            "initial_stock": 24,
        },
        headers=headers,
    )
    assert p1_resp.status_code == 201

    p2_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Gansito Marinela 50g",
            "sku": f"GAN-50-{suffix}",
            "price_mxn": 22.00,
            "cost_mxn": 16.50,
            "initial_stock": 15,
        },
        headers=headers,
    )
    assert p2_resp.status_code == 201

    # 3. Consultar catálogo público (SIN HEADERS DE AUTENTICACIÓN)
    cat_resp = await client.get(f"/api/v1/public/catalog/{slug}")
    assert cat_resp.status_code == 200
    data = cat_resp.json()

    # 4. Validar estructura
    assert data["store"]["name"] == f"Abarrotes Don Pepe {suffix}"
    assert data["store"]["slug"] == slug
    assert data["store"]["is_catalog_enabled"] is True
    assert data["total_products"] == 2
    assert len(data["products"]) == 2

    # Validar precios en MXN y stock
    coca = next(p for p in data["products"] if p["name"] == "Coca-Cola 600ml")
    assert Decimal(str(coca["price_mxn"])) == Decimal("18.50")
    assert coca["in_stock"] is True
    assert Decimal(str(coca["available_stock"])) == Decimal("24.00")


@pytest.mark.asyncio
async def test_public_catalog_filters_inactive_products(client: AsyncClient):
    """
    Test 2: El catálogo público solo muestra productos activos (is_active=True).
    """
    suffix = uuid.uuid4().hex[:6]
    slug = f"filtro-cat-{suffix}"
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Filtro {suffix}",
            "slug": slug,
            "full_name": "Dueño Filtro",
            "email": f"filtro_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Producto activo
    await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Leche Lala 1L",
            "sku": f"LALA-1L-{suffix}",
            "price_mxn": 28.00,
            "initial_stock": 10,
        },
        headers=headers,
    )

    # Producto creado y luego desactivado vía PUT
    p2_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Pan Bimbo Descontinuado",
            "sku": f"PAN-DISC-{suffix}",
            "price_mxn": 45.00,
            "initial_stock": 5,
        },
        headers=headers,
    )
    p2_id = p2_resp.json()["id"]
    await client.put(
        f"/api/v1/inventory/products/{p2_id}",
        json={
            "name": "Pan Bimbo Descontinuado",
            "price_mxn": 45.00,
            "is_active": False,
        },
        headers=headers,
    )

    # Consultar catálogo público
    cat_resp = await client.get(f"/api/v1/public/catalog/{slug}")
    assert cat_resp.status_code == 200
    data = cat_resp.json()

    assert data["total_products"] == 1
    assert data["products"][0]["name"] == "Leche Lala 1L"


@pytest.mark.asyncio
async def test_public_product_detail_and_og_metadata(client: AsyncClient):
    """
    Test 3: Ficha individual de producto y metadatos OpenGraph para SSR (Const. Art. 7.4).
    """
    suffix = uuid.uuid4().hex[:6]
    slug = f"og-store-{suffix}"
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Metadatos {suffix}",
            "slug": slug,
            "full_name": "Dueño Meta",
            "email": f"meta_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Aceite Nutrioli 946ml",
            "sku": f"NUT-946-{suffix}",
            "price_mxn": 46.50,
            "initial_stock": 20,
        },
        headers=headers,
    )
    prod_id = prod_resp.json()["id"]

    # 1. Ficha individual pública
    detail_resp = await client.get(f"/api/v1/public/catalog/{slug}/products/{prod_id}")
    assert detail_resp.status_code == 200
    det = detail_resp.json()
    assert det["name"] == "Aceite Nutrioli 946ml"
    assert Decimal(str(det["price_mxn"])) == Decimal("46.50")
    assert det["store_slug"] == slug

    # 2. Metadatos OpenGraph de producto
    og_resp = await client.get(f"/api/v1/public/catalog/{slug}/og-metadata?product_id={prod_id}")
    assert og_resp.status_code == 200
    og = og_resp.json()
    assert "Aceite Nutrioli 946ml" in og["og_title"]
    assert Decimal(str(og["og_price_amount"])) == Decimal("46.50")
    assert og["og_price_currency"] == "MXN"

    # 3. Metadatos OpenGraph a nivel tienda
    og_store_resp = await client.get(f"/api/v1/public/catalog/{slug}/og-metadata")
    assert og_store_resp.status_code == 200
    og_s = og_store_resp.json()
    assert f"Tienda Metadatos {suffix}" in og_s["og_title"]
    assert og_s["og_price_amount"] is None


@pytest.mark.asyncio
async def test_build_whatsapp_order_delivery_mode(client: AsyncClient):
    """
    Test 4: Construcción de pedido para WhatsApp con entrega a domicilio y cambio en efectivo (RF-24).
    """
    suffix = uuid.uuid4().hex[:6]
    slug = f"delivery-store-{suffix}"
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Express {suffix}",
            "slug": slug,
            "full_name": "Dueño Express",
            "email": f"express_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Configurar parámetros del catálogo de la tienda
    await client.put(
        "/api/v1/catalog-settings",
        json={
            "whatsapp_number": "5512345678",
            "delivery_fee_mxn": 30.00,
            "min_order_amount_mxn": 50.00,
            "delivery_enabled": True,
        },
        headers=headers,
    )

    # Crear productos
    p1 = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Refresco Jarrito 2L", "sku": f"JAR-2L-{suffix}", "price_mxn": 25.00, "initial_stock": 30},
        headers=headers,
    )
    p2 = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Papas Sabritas Sal 45g", "sku": f"SAB-45-{suffix}", "price_mxn": 20.00, "initial_stock": 20},
        headers=headers,
    )
    p1_id = p1.json()["id"]
    p2_id = p2.json()["id"]

    # Cliente arma carrito: 2 Refrescos ($50) + 1 Papas ($20) = $70 Subtotal + $30 Envío = $100 Total
    # Paga con billete de $200 MXN -> Cambio $100 MXN
    order_payload = {
        "customer_name": "Juan Pérez",
        "customer_phone": "5599887766",
        "delivery_method": "DELIVERY",
        "delivery_address": "Av. Universidad #456, Depto 3B",
        "payment_method": "CASH",
        "cash_tendered_mxn": 200.00,
        "items": [
            {"product_id": p1_id, "quantity": 2, "notes": "Bien frío por favor"},
            {"product_id": p2_id, "quantity": 1},
        ],
        "order_notes": "Tocar timbre 3B",
    }

    order_resp = await client.post(f"/api/v1/public/catalog/{slug}/build-whatsapp-order", json=order_payload)
    assert order_resp.status_code == 200
    data = order_resp.json()

    assert Decimal(str(data["subtotal_mxn"])) == Decimal("70.00")
    assert Decimal(str(data["delivery_fee_mxn"])) == Decimal("30.00")
    assert Decimal(str(data["total_mxn"])) == Decimal("100.00")
    assert Decimal(str(data["change_mxn"])) == Decimal("100.00")
    assert data["item_count"] == 2

    # Validar que el link wa.me contenga el número y texto codificado
    assert "wa.me/525512345678" in data["wa_link"]
    assert "Refresco%20Jarrito%202L" in data["wa_link"] or "Refresco" in data["wa_link"]
    assert "Refresco Jarrito 2L" in data["formatted_text"]
    assert "Av. Universidad" in data["formatted_text"]


@pytest.mark.asyncio
async def test_build_whatsapp_order_pickup_mode(client: AsyncClient):
    """
    Test 5: Construcción de pedido para recoger en tienda física (sin costo de envío).
    """
    suffix = uuid.uuid4().hex[:6]
    slug = f"pickup-store-{suffix}"
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Pickup {suffix}",
            "slug": slug,
            "full_name": "Dueño Pickup",
            "email": f"pickup_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    p = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Huevo Blanco 1kg", "sku": f"HUE-1K-{suffix}", "price_mxn": 48.00, "initial_stock": 50},
        headers=headers,
    )
    p_id = p.json()["id"]

    order_payload = {
        "customer_name": "María López",
        "delivery_method": "PICKUP",
        "payment_method": "TRANSFER",
        "items": [{"product_id": p_id, "quantity": 2}],
    }

    order_resp = await client.post(f"/api/v1/public/catalog/{slug}/build-whatsapp-order", json=order_payload)
    assert order_resp.status_code == 200
    data = order_resp.json()

    assert Decimal(str(data["subtotal_mxn"])) == Decimal("96.00")
    assert Decimal(str(data["delivery_fee_mxn"])) == Decimal("0.00")
    assert Decimal(str(data["total_mxn"])) == Decimal("96.00")
    assert data["change_mxn"] is None
    assert "Recoger en tienda" in data["formatted_text"]


@pytest.mark.asyncio
async def test_build_whatsapp_order_min_amount_rejection(client: AsyncClient):
    """
    Test 6: Rechazo cuando el subtotal es menor al monto mínimo de compra en MXN.
    """
    suffix = uuid.uuid4().hex[:6]
    slug = f"min-store-{suffix}"
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Mínimo {suffix}",
            "slug": slug,
            "full_name": "Dueño Mínimo",
            "email": f"min_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Configurar pedido mínimo de $150 MXN
    await client.put(
        "/api/v1/catalog-settings",
        json={"min_order_amount_mxn": 150.00},
        headers=headers,
    )

    p = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Chicles Clorets", "sku": f"CHIC-{suffix}", "price_mxn": 12.00, "initial_stock": 100},
        headers=headers,
    )
    p_id = p.json()["id"]

    # Pedido de solo $24 MXN (menor a $150 MXN)
    order_payload = {
        "customer_name": "Pedro",
        "delivery_method": "PICKUP",
        "items": [{"product_id": p_id, "quantity": 2}],
    }
    resp = await client.post(f"/api/v1/public/catalog/{slug}/build-whatsapp-order", json=order_payload)
    assert resp.status_code == 400
    assert "menor al pedido" in resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_catalog_settings_update_by_owner(client: AsyncClient):
    """
    Test 7: Gestión y actualización de configuraciones del catálogo por el comercio (RF-26).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Settings {suffix}",
            "slug": f"sett-{suffix}",
            "full_name": "Dueño Settings",
            "email": f"sett_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Consultar configuración por defecto
    get_resp = await client.get("/api/v1/catalog-settings", headers=headers)
    assert get_resp.status_code == 200
    initial = get_resp.json()
    assert initial["is_catalog_enabled"] is True
    assert Decimal(str(initial["min_order_amount_mxn"])) == Decimal("0.00")

    # Modificar parámetros
    put_resp = await client.put(
        "/api/v1/catalog-settings",
        json={
            "whatsapp_number": "5599881122",
            "welcome_message": "¡Bienvenidos a nuestra tiendita en línea!",
            "min_order_amount_mxn": 80.00,
            "delivery_fee_mxn": 25.00,
            "delivery_enabled": True,
            "pickup_enabled": True,
            "business_hours": "Lunes a Sábado de 8:00 AM a 9:00 PM",
        },
        headers=headers,
    )
    assert put_resp.status_code == 200
    updated = put_resp.json()
    assert updated["whatsapp_number"] == "5599881122"
    assert updated["welcome_message"] == "¡Bienvenidos a nuestra tiendita en línea!"
    assert Decimal(str(updated["min_order_amount_mxn"])) == Decimal("80.00")
    assert Decimal(str(updated["delivery_fee_mxn"])) == Decimal("25.00")
    assert updated["business_hours"] == "Lunes a Sábado de 8:00 AM a 9:00 PM"


@pytest.mark.asyncio
async def test_public_catalog_multi_tenant_isolation(client: AsyncClient):
    """
    Test 8: Aislamiento estricto multi-tenant:
    El catálogo de la Tienda A no expone productos de la Tienda B,
    y armar pedidos con productos ajenos es rechazado.
    """
    # Crear Tienda A
    suffix_a = uuid.uuid4().hex[:6]
    slug_a = f"store-a-{suffix_a}"
    reg_a = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda A {suffix_a}",
            "slug": slug_a,
            "full_name": "Dueño A",
            "email": f"a_{suffix_a}@tienda.mx",
            "password": "password123",
        },
    )
    headers_a = {"Authorization": f"Bearer {reg_a.json()['access_token']}"}

    p_a = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Producto A", "sku": f"PROD-A-{suffix_a}", "price_mxn": 100.00, "initial_stock": 10},
        headers=headers_a,
    )
    prod_a_id = p_a.json()["id"]

    # Crear Tienda B
    suffix_b = uuid.uuid4().hex[:6]
    slug_b = f"store-b-{suffix_b}"
    reg_b = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda B {suffix_b}",
            "slug": slug_b,
            "full_name": "Dueño B",
            "email": f"b_{suffix_b}@tienda.mx",
            "password": "password123",
        },
    )
    headers_b = {"Authorization": f"Bearer {reg_b.json()['access_token']}"}

    p_b = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Producto B", "sku": f"PROD-B-{suffix_b}", "price_mxn": 200.00, "initial_stock": 10},
        headers=headers_b,
    )
    prod_b_id = p_b.json()["id"]

    # Consultar Catálogo A -> Solo debe ver Producto A
    cat_a = await client.get(f"/api/v1/public/catalog/{slug_a}")
    assert cat_a.status_code == 200
    assert cat_a.json()["total_products"] == 1
    assert cat_a.json()["products"][0]["name"] == "Producto A"

    # Intentar pedir Producto B en la tienda A -> Rechazado
    cross_order = {
        "customer_name": "Infiltrado",
        "delivery_method": "PICKUP",
        "items": [{"product_id": prod_b_id, "quantity": 1}],
    }
    cross_resp = await client.post(f"/api/v1/public/catalog/{slug_a}/build-whatsapp-order", json=cross_order)
    assert cross_resp.status_code == 400


@pytest.mark.asyncio
async def test_public_catalog_disabled_suspension(client: AsyncClient):
    """
    Test 9: Cuando el comercio deshabilita el catálogo (is_catalog_enabled=False),
    los clientes reciben 403 Forbidden.
    """
    suffix = uuid.uuid4().hex[:6]
    slug = f"disabled-store-{suffix}"
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Cerrada {suffix}",
            "slug": slug,
            "full_name": "Dueño Cerrado",
            "email": f"cerrado_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Deshabilitar catálogo
    await client.put(
        "/api/v1/catalog-settings",
        json={"is_catalog_enabled": False},
        headers=headers,
    )

    # Cliente intenta acceder
    resp = await client.get(f"/api/v1/public/catalog/{slug}")
    assert resp.status_code == 403
    assert "suspendido" in resp.json()["detail"].lower()


async def _register_store(client: AsyncClient, prefix: str):
    """Registra un comercio y devuelve (slug, headers, nombre)."""
    suffix = uuid.uuid4().hex[:6]
    slug = f"{prefix}-{suffix}"
    name = f"Tienda {prefix.title()} {suffix}"
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": name,
            "slug": slug,
            "full_name": "Dueño Pedidos",
            "email": f"{prefix}_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201, reg_resp.text
    headers = {"Authorization": f"Bearer {reg_resp.json()['access_token']}"}
    return slug, headers, name


@pytest.mark.asyncio
async def test_catalog_settings_expose_store_slug_and_clear_text_fields(client: AsyncClient):
    """
    Integración con "Mi catálogo" (Flutter, Sep 2026): la configuración trae el nombre y
    el slug del comercio para armar el enlace público, y un texto vacío borra el campo
    (así se quita el número de WhatsApp desde la app).
    """
    slug, headers, name = await _register_store(client, "slugsett")

    get_resp = await client.get("/api/v1/catalog-settings", headers=headers)
    assert get_resp.status_code == 200
    body = get_resp.json()
    assert body["store_slug"] == slug
    assert body["store_name"] == name

    put_resp = await client.put(
        "/api/v1/catalog-settings",
        json={"whatsapp_number": "5512345678"},
        headers=headers,
    )
    assert put_resp.status_code == 200
    assert put_resp.json()["whatsapp_number"] == "5512345678"

    clear_resp = await client.put(
        "/api/v1/catalog-settings",
        json={"whatsapp_number": "   "},
        headers=headers,
    )
    assert clear_resp.status_code == 200
    assert clear_resp.json()["whatsapp_number"] is None
    assert clear_resp.json()["store_slug"] == slug

    # Lo que se guardó es lo que se lee después
    again = await client.get("/api/v1/catalog-settings", headers=headers)
    assert again.json()["whatsapp_number"] is None


@pytest.mark.asyncio
async def test_submit_catalog_order_assigns_folio_and_ticket_is_public(client: AsyncClient):
    """
    RF-24 (iteración 3 de QA de la Tarea 13.2): el pedido se registra con folio
    `P-YYMMDD-XXXX`, el ticket se consulta sin sesión y trae la instantánea de
    los renglones con los mismos totales que la vista previa.
    """
    slug, headers, name = await _register_store(client, "pedidos")

    p_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Leche Lala 1L",
            "sku": f"LAL-1L-{slug[-6:]}",
            "price_mxn": 28.50,
            "cost_mxn": 22.00,
            "initial_stock": 30,
        },
        headers=headers,
    )
    assert p_resp.status_code == 201, p_resp.text
    product_id = p_resp.json()["id"]

    set_resp = await client.put(
        "/api/v1/catalog-settings",
        json={"whatsapp_number": "5511112222", "delivery_fee_mxn": 15.00},
        headers=headers,
    )
    assert set_resp.status_code == 200

    payload = {
        "customer_name": "Ana López",
        "customer_phone": "5533334444",
        "delivery_method": "DELIVERY",
        "delivery_address": "Calle Sol 12, Col. Centro",
        "payment_method": "CASH",
        "cash_tendered_mxn": 100.00,
        "items": [{"product_id": product_id, "quantity": 2, "notes": "bien fría"}],
        "order_notes": "Tocar el timbre",
    }

    preview = await client.post(f"/api/v1/public/catalog/{slug}/build-whatsapp-order", json=payload)
    assert preview.status_code == 200, preview.text

    submit = await client.post(f"/api/v1/public/catalog/{slug}/orders", json=payload)
    assert submit.status_code == 201, submit.text
    order = submit.json()
    assert order["folio"].startswith("P-") and len(order["folio"]) == 13
    assert order["store_slug"] == slug
    assert order["store_name"] == name
    assert Decimal(str(order["subtotal_mxn"])) == Decimal("57.00")
    assert Decimal(str(order["delivery_fee_mxn"])) == Decimal("15.00")
    assert Decimal(str(order["total_mxn"])) == Decimal("72.00")
    assert Decimal(str(order["change_mxn"])) == Decimal("28.00")
    assert order["formatted_text"] == preview.json()["formatted_text"]
    assert order["wa_link"].startswith("https://wa.me/525511112222?text=")
    assert len(order["items"]) == 1
    item = order["items"][0]
    assert item["product_id"] == product_id
    assert item["name"] == "Leche Lala 1L"
    assert Decimal(str(item["quantity"])) == Decimal("2")
    assert item["notes"] == "bien fría"

    # El ticket se abre sin token pero con la clave del enlace (folio + ?k=),
    # que sólo recibe quien registró el pedido. Sin clave o con otra → 404
    # (no se revela si el folio existe: sería adivinable).
    key = order["access_key"]
    assert key and len(key) >= 10
    ticket = await client.get(f"/api/v1/public/catalog/{slug}/orders/{order['folio'].lower()}?k={key}")
    assert ticket.status_code == 200, ticket.text
    assert ticket.json()["folio"] == order["folio"]
    assert ticket.json()["customer_name"] == "Ana López"
    assert ticket.json()["delivery_address"] == "Calle Sol 12, Col. Centro"
    assert ticket.json()["access_key"] is None  # el GET público no la devuelve

    no_key = await client.get(f"/api/v1/public/catalog/{slug}/orders/{order['folio']}")
    assert no_key.status_code == 404
    bad_key = await client.get(f"/api/v1/public/catalog/{slug}/orders/{order['folio']}?k=nope")
    assert bad_key.status_code == 404
    missing = await client.get(f"/api/v1/public/catalog/{slug}/orders/P-000000-ZZZZ?k={key}")
    assert missing.status_code == 404
    no_store = await client.get(f"/api/v1/public/catalog/no-existe-{slug}/orders/{order['folio']}?k={key}")
    assert no_store.status_code == 404


@pytest.mark.asyncio
async def test_submit_catalog_order_respects_store_rules(client: AsyncClient):
    """El registro con folio aplica las mismas reglas que la vista previa (pedido mínimo)."""
    slug, headers, _ = await _register_store(client, "reglas")

    p_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Chicle Trident", "sku": f"TRI-{slug[-6:]}", "price_mxn": 12.00, "cost_mxn": 8.00, "initial_stock": 50},
        headers=headers,
    )
    product_id = p_resp.json()["id"]
    await client.put("/api/v1/catalog-settings", json={"min_order_amount_mxn": 100.00}, headers=headers)

    submit = await client.post(
        f"/api/v1/public/catalog/{slug}/orders",
        json={"customer_name": "Luis", "items": [{"product_id": product_id, "quantity": 1}]},
    )
    assert submit.status_code == 400
    assert "pedido mínimo" in submit.json()["detail"]
