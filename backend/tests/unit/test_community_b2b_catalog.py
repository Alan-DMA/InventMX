# Importación del módulo decimal para cálculos monetarios exactos
from decimal import Decimal
# Importación del módulo uuid para generar identificadores únicos
import uuid
# Importación de pytest para pruebas asíncronas
import pytest
# Importación de AsyncClient de httpx para peticiones HTTP asíncronas
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_publish_b2b_wholesale_listing(client: AsyncClient):
    """
    Test 1: Publicación de oferta mayorista en el catálogo comunitario B2B (RF-27 / Const. Art. 4.3).
    Verifica que el comercio pueda publicar lotes con precio mayorista en MXN ($).
    """
    # 1. Registrar comercio vendedor
    suffix = uuid.uuid4().hex[:6]
    seller_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Distribuidora Central {suffix}",
            "slug": f"distribuidora-central-{suffix}",
            "full_name": "Distribuidor Mayorista",
            "email": f"distribuidor_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    assert seller_reg.status_code == 201
    seller_token = seller_reg.json()["access_token"]
    seller_headers = {"Authorization": f"Bearer {seller_token}"}

    # 2. Crear producto base en el inventario del vendedor
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Bulto de Azúcar Estándar 50kg {suffix}",
            "sku": f"AZU-50K-{suffix}",
            "price_mxn": 950.00,
            "cost_mxn": 780.00,
            "initial_stock": 100,
        },
        headers=seller_headers,
    )
    assert prod_resp.status_code == 201
    product_id = prod_resp.json()["id"]

    # 3. Publicar oferta mayorista en el marketplace B2B
    listing_resp = await client.post(
        "/api/v1/b2b/listings",
        json={
            "product_id": product_id,
            "wholesale_price_mxn": 820.00,
            "min_wholesale_quantity": 5,
            "available_b2b_stock": 80,
            "location_postal_code": "06000",
            "location_city": "Ciudad de México",
            "notes": "Entrega en bodega o flete consolidado a acordar",
        },
        headers=seller_headers,
    )
    assert listing_resp.status_code == 201
    data = listing_resp.json()

    # 4. Validar DTO de respuesta
    assert data["product_id"] == product_id
    assert Decimal(str(data["wholesale_price_mxn"])) == Decimal("820.00")
    assert Decimal(str(data["min_wholesale_quantity"])) == Decimal("5")
    assert Decimal(str(data["available_b2b_stock"])) == Decimal("80")
    assert data["location_postal_code"] == "06000"
    assert data["location_city"] == "Ciudad de México"
    assert data["is_active"] is True


@pytest.mark.asyncio
async def test_get_my_b2b_listings(client: AsyncClient):
    """
    Test 2: Consulta de ofertas mayoristas publicadas por el comercio autenticado (/my-listings).
    """
    suffix = uuid.uuid4().hex[:6]
    seller_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Don Lucho {suffix}",
            "slug": f"abarrotes-lucho-{suffix}",
            "full_name": "Lucho Pérez",
            "email": f"lucho_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    seller_token = seller_reg.json()["access_token"]
    seller_headers = {"Authorization": f"Bearer {seller_token}"}

    # Crear producto
    p_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Aceite Vegetal 12x1L {suffix}",
            "sku": f"ACE-12L-{suffix}",
            "price_mxn": 480.00,
            "cost_mxn": 390.00,
            "initial_stock": 50,
        },
        headers=seller_headers,
    )
    product_id = p_resp.json()["id"]

    # Publicar oferta B2B
    await client.post(
        "/api/v1/b2b/listings",
        json={
            "product_id": product_id,
            "wholesale_price_mxn": 410.00,
            "min_wholesale_quantity": 10,
            "available_b2b_stock": 40,
            "location_city": "Guadalajara",
        },
        headers=seller_headers,
    )

    # Consultar mis publicaciones
    my_resp = await client.get("/api/v1/b2b/my-listings", headers=seller_headers)
    assert my_resp.status_code == 200
    listings = my_resp.json()
    assert len(listings) >= 1
    assert any(l["product_id"] == product_id for l in listings)


@pytest.mark.asyncio
async def test_update_b2b_listing(client: AsyncClient):
    """
    Test 3: Actualización de precio, lote mínimo y disponibilidad de una oferta B2B.
    """
    suffix = uuid.uuid4().hex[:6]
    seller_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Comercializadora Norte {suffix}",
            "slug": f"comercializadora-norte-{suffix}",
            "full_name": "Gerente Norte",
            "email": f"norte_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    seller_token = seller_reg.json()["access_token"]
    seller_headers = {"Authorization": f"Bearer {seller_token}"}

    p_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Frijol Negro 25kg {suffix}",
            "sku": f"FRI-25K-{suffix}",
            "price_mxn": 650.00,
            "cost_mxn": 500.00,
            "initial_stock": 60,
        },
        headers=seller_headers,
    )
    product_id = p_resp.json()["id"]

    listing_resp = await client.post(
        "/api/v1/b2b/listings",
        json={
            "product_id": product_id,
            "wholesale_price_mxn": 560.00,
            "min_wholesale_quantity": 4,
            "available_b2b_stock": 50,
            "location_city": "Monterrey",
        },
        headers=seller_headers,
    )
    listing_id = listing_resp.json()["id"]

    # Actualizar la oferta
    update_resp = await client.put(
        f"/api/v1/b2b/listings/{listing_id}",
        json={
            "wholesale_price_mxn": 540.00,
            "min_wholesale_quantity": 6,
            "notes": "Precio especial por volumen actualizado",
        },
        headers=seller_headers,
    )
    assert update_resp.status_code == 200
    updated_data = update_resp.json()
    assert Decimal(str(updated_data["wholesale_price_mxn"])) == Decimal("540.00")
    assert Decimal(str(updated_data["min_wholesale_quantity"])) == Decimal("6")
    assert updated_data["notes"] == "Precio especial por volumen actualizado"


@pytest.mark.asyncio
async def test_b2b_marketplace_search_and_tenant_isolation(client: AsyncClient):
    """
    Test 4: Búsqueda federada en el marketplace B2B excluyendo publicaciones propias.
    """
    # 1. Registrar Vendedor
    suffix_s = uuid.uuid4().hex[:6]
    seller_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Bodega del Bajío {suffix_s}",
            "slug": f"bodega-bajio-{suffix_s}",
            "full_name": "Bajío Vendedor",
            "email": f"bajio_{suffix_s}@nexus.mx",
            "password": "password123",
        },
    )
    seller_token = seller_reg.json()["access_token"]
    seller_headers = {"Authorization": f"Bearer {seller_token}"}

    # Publicar producto
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Huevo Blanco 360 piezas {suffix_s}",
            "sku": f"HUE-360-{suffix_s}",
            "price_mxn": 890.00,
            "cost_mxn": 750.00,
            "initial_stock": 30,
        },
        headers=seller_headers,
    )
    prod_id = prod_resp.json()["id"]

    await client.post(
        "/api/v1/b2b/listings",
        json={
            "product_id": prod_id,
            "wholesale_price_mxn": 780.00,
            "min_wholesale_quantity": 3,
            "available_b2b_stock": 25,
            "location_city": "León",
            "location_postal_code": "37000",
        },
        headers=seller_headers,
    )

    # 2. Registrar Comprador
    suffix_b = uuid.uuid4().hex[:6]
    buyer_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Minisuper La Esquina {suffix_b}",
            "slug": f"minisuper-esquina-{suffix_b}",
            "full_name": "Comprador Esquina",
            "email": f"esquina_{suffix_b}@nexus.mx",
            "password": "password123",
        },
    )
    buyer_token = buyer_reg.json()["access_token"]
    buyer_headers = {"Authorization": f"Bearer {buyer_token}"}

    # 3. Comprador busca en el marketplace por ciudad y búsqueda
    market_resp = await client.get(
        f"/api/v1/b2b/marketplace?search=Huevo&city=León",
        headers=buyer_headers,
    )
    assert market_resp.status_code == 200
    market_items = market_resp.json()
    assert len(market_items) >= 1
    found = next((itm for itm in market_items if itm["product_id"] == prod_id), None)
    assert found is not None
    assert Decimal(str(found["wholesale_price_mxn"])) == Decimal("780.00")

    # 4. Validar aislamiento: El vendedor NO debe ver su propia oferta en el marketplace de compra
    seller_market_resp = await client.get(
        f"/api/v1/b2b/marketplace?search=Huevo",
        headers=seller_headers,
    )
    assert seller_market_resp.status_code == 200
    seller_items = seller_market_resp.json()
    assert not any(itm["product_id"] == prod_id for itm in seller_items)


@pytest.mark.asyncio
async def test_create_b2b_order_success(client: AsyncClient):
    """
    Test 5: Emisión exitosa de pedido mayorista B2B (RF-27 / Const. Art. 7.5).
    """
    # 1. Setup Vendedor
    suffix_s = uuid.uuid4().hex[:6]
    seller_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Mayorista Puebla {suffix_s}",
            "slug": f"mayorista-puebla-{suffix_s}",
            "full_name": "Don Ramón",
            "email": f"ramon_{suffix_s}@nexus.mx",
            "password": "password123",
        },
    )
    seller_token = seller_reg.json()["access_token"]
    seller_tenant_id = seller_reg.json()["user"]["tenant_id"]
    seller_headers = {"Authorization": f"Bearer {seller_token}"}

    # Producto y oferta
    p_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Leche Entera Caja 12L {suffix_s}",
            "sku": f"LEC-12L-{suffix_s}",
            "price_mxn": 310.00,
            "cost_mxn": 240.00,
            "initial_stock": 50,
        },
        headers=seller_headers,
    )
    prod_id = p_resp.json()["id"]

    list_resp = await client.post(
        "/api/v1/b2b/listings",
        json={
            "product_id": prod_id,
            "wholesale_price_mxn": 260.00,
            "min_wholesale_quantity": 5,
            "available_b2b_stock": 40,
        },
        headers=seller_headers,
    )
    listing_id = list_resp.json()["id"]

    # 2. Setup Comprador
    suffix_b = uuid.uuid4().hex[:6]
    buyer_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes San Juan {suffix_b}",
            "slug": f"abarrotes-sanjuan-{suffix_b}",
            "full_name": "Doña María",
            "email": f"maria_{suffix_b}@nexus.mx",
            "password": "password123",
        },
    )
    buyer_token = buyer_reg.json()["access_token"]
    buyer_headers = {"Authorization": f"Bearer {buyer_token}"}

    # 3. Comprador emite pedido B2B por 8 unidades
    order_resp = await client.post(
        "/api/v1/b2b/orders",
        json={
            "seller_tenant_id": seller_tenant_id,
            "delivery_type": "DELIVERY",
            "delivery_address": "Calle 5 de Mayo #45, Puebla",
            "notes": "Entregar en horario matutino",
            "items": [
                {
                    "b2b_listing_id": listing_id,
                    "quantity": 8,
                }
            ],
        },
        headers=buyer_headers,
    )
    assert order_resp.status_code == 201
    order_data = order_resp.json()

    # 4. Validar DTO
    assert order_data["order_number"].startswith("B2B-")
    assert order_data["status"] == "PENDING"
    assert order_data["delivery_type"] == "DELIVERY"
    # Total = 8 * 260.00 = 2080.00
    assert Decimal(str(order_data["total_mxn"])) == Decimal("2080.00")
    assert len(order_data["items"]) == 1
    assert Decimal(str(order_data["items"][0]["unit_price_mxn"])) == Decimal("260.00")
    assert Decimal(str(order_data["items"][0]["subtotal_mxn"])) == Decimal("2080.00")


@pytest.mark.asyncio
async def test_reject_b2b_order_below_min_quantity(client: AsyncClient):
    """
    Test 6: Rechazo de pedido B2B si la cantidad solicitada es menor al lote mínimo (RF-27).
    """
    suffix_s = uuid.uuid4().hex[:6]
    seller_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Distribuidora Lote {suffix_s}",
            "slug": f"dist-lote-{suffix_s}",
            "full_name": "Vendedor Lote",
            "email": f"lote_{suffix_s}@nexus.mx",
            "password": "password123",
        },
    )
    seller_token = seller_reg.json()["access_token"]
    seller_tenant_id = seller_reg.json()["user"]["tenant_id"]
    seller_headers = {"Authorization": f"Bearer {seller_token}"}

    p_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Arroz Grano Largo 50kg {suffix_s}",
            "sku": f"ARR-50K-{suffix_s}",
            "price_mxn": 800.00,
            "cost_mxn": 600.00,
            "initial_stock": 50,
        },
        headers=seller_headers,
    )
    prod_id = p_resp.json()["id"]

    list_resp = await client.post(
        "/api/v1/b2b/listings",
        json={
            "product_id": prod_id,
            "wholesale_price_mxn": 700.00,
            "min_wholesale_quantity": 10,
            "available_b2b_stock": 40,
        },
        headers=seller_headers,
    )
    listing_id = list_resp.json()["id"]

    # Comprador
    suffix_b = uuid.uuid4().hex[:6]
    buyer_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tiendita Sol {suffix_b}",
            "slug": f"tiendita-sol-{suffix_b}",
            "full_name": "Comprador Sol",
            "email": f"sol_{suffix_b}@nexus.mx",
            "password": "password123",
        },
    )
    buyer_token = buyer_reg.json()["access_token"]
    buyer_headers = {"Authorization": f"Bearer {buyer_token}"}

    # Intento de pedir solo 4 unidades cuando el mínimo es 10
    fail_resp = await client.post(
        "/api/v1/b2b/orders",
        json={
            "seller_tenant_id": seller_tenant_id,
            "delivery_type": "PICKUP",
            "items": [{"b2b_listing_id": listing_id, "quantity": 4}],
        },
        headers=buyer_headers,
    )
    assert fail_resp.status_code == 400
    assert "lote mínimo" in fail_resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_reject_b2b_self_trade(client: AsyncClient):
    """
    Test 7: Rechazo de auto-pedidos B2B (un comercio no puede emitirse pedidos a sí mismo).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Auto Comercio {suffix}",
            "slug": f"auto-comercio-{suffix}",
            "full_name": "Dueño Auto",
            "email": f"auto_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    tenant_id = reg_resp.json()["user"]["tenant_id"]
    headers = {"Authorization": f"Bearer {token}"}

    p_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Pasta 200g {suffix}",
            "sku": f"PAS-200-{suffix}",
            "price_mxn": 12.00,
            "cost_mxn": 8.00,
            "initial_stock": 100,
        },
        headers=headers,
    )
    prod_id = p_resp.json()["id"]

    list_resp = await client.post(
        "/api/v1/b2b/listings",
        json={
            "product_id": prod_id,
            "wholesale_price_mxn": 9.50,
            "min_wholesale_quantity": 20,
            "available_b2b_stock": 80,
        },
        headers=headers,
    )
    listing_id = list_resp.json()["id"]

    # Intento de comprarse a sí mismo
    self_resp = await client.post(
        "/api/v1/b2b/orders",
        json={
            "seller_tenant_id": tenant_id,
            "delivery_type": "PICKUP",
            "items": [{"b2b_listing_id": listing_id, "quantity": 25}],
        },
        headers=headers,
    )
    assert self_resp.status_code == 400
    assert "propio comercio" in self_resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_seller_accepts_b2b_order_and_stock_discount(client: AsyncClient):
    """
    Test 8: Flujo de aceptación de pedido por el vendedor y descuento de stock mayorista.
    """
    # 1. Setup Vendedor
    suffix_s = uuid.uuid4().hex[:6]
    seller_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Proveedor del Centro {suffix_s}",
            "slug": f"prov-centro-{suffix_s}",
            "full_name": "Proveedor Don Raúl",
            "email": f"raul_{suffix_s}@nexus.mx",
            "password": "password123",
        },
    )
    seller_token = seller_reg.json()["access_token"]
    seller_tenant_id = seller_reg.json()["user"]["tenant_id"]
    seller_headers = {"Authorization": f"Bearer {seller_token}"}

    p_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Detergente Multiusos 10kg {suffix_s}",
            "sku": f"DET-10K-{suffix_s}",
            "price_mxn": 320.00,
            "cost_mxn": 220.00,
            "initial_stock": 40,
        },
        headers=seller_headers,
    )
    prod_id = p_resp.json()["id"]

    list_resp = await client.post(
        "/api/v1/b2b/listings",
        json={
            "product_id": prod_id,
            "wholesale_price_mxn": 250.00,
            "min_wholesale_quantity": 5,
            "available_b2b_stock": 30,
        },
        headers=seller_headers,
    )
    listing_id = list_resp.json()["id"]

    # 2. Setup Comprador
    suffix_b = uuid.uuid4().hex[:6]
    buyer_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes La Luna {suffix_b}",
            "slug": f"abarrotes-luna-{suffix_b}",
            "full_name": "Compradora Luna",
            "email": f"luna_{suffix_b}@nexus.mx",
            "password": "password123",
        },
    )
    buyer_token = buyer_reg.json()["access_token"]
    buyer_headers = {"Authorization": f"Bearer {buyer_token}"}

    # 3. Comprador emite pedido por 10 unidades
    order_resp = await client.post(
        "/api/v1/b2b/orders",
        json={
            "seller_tenant_id": seller_tenant_id,
            "delivery_type": "DELIVERY",
            "items": [{"b2b_listing_id": listing_id, "quantity": 10}],
        },
        headers=buyer_headers,
    )
    order_id = order_resp.json()["id"]

    # 4. Vendedor acepta el pedido
    status_resp = await client.patch(
        f"/api/v1/b2b/orders/{order_id}/status",
        json={
            "status": "ACCEPTED",
            "notes": "Pedido aceptado, preparando envío para mañana",
        },
        headers=seller_headers,
    )
    assert status_resp.status_code == 200
    assert status_resp.json()["status"] == "ACCEPTED"

    # 5. Validar que el stock mayorista disponible en la publicación se redujo (30 - 10 = 20)
    my_listings = await client.get("/api/v1/b2b/my-listings", headers=seller_headers)
    listing_updated = next(l for l in my_listings.json() if l["id"] == listing_id)
    assert Decimal(str(listing_updated["available_b2b_stock"])) == Decimal("20.00")


@pytest.mark.asyncio
async def test_b2b_orders_sent_and_received_filters(client: AsyncClient):
    """
    Test 9: Consulta de pedidos emitidos y recibidos con filtros de rol (/orders/sent y /orders/received).
    """
    # Setup Vendedor
    suffix_s = uuid.uuid4().hex[:6]
    seller_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Ventas Mayoristas MX {suffix_s}",
            "slug": f"ventas-mx-{suffix_s}",
            "full_name": "Vendedor MX",
            "email": f"mx_{suffix_s}@nexus.mx",
            "password": "password123",
        },
    )
    seller_token = seller_reg.json()["access_token"]
    seller_tenant_id = seller_reg.json()["user"]["tenant_id"]
    seller_headers = {"Authorization": f"Bearer {seller_token}"}

    p_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Galletas Surtidas 1kg {suffix_s}",
            "sku": f"GAL-1K-{suffix_s}",
            "price_mxn": 85.00,
            "cost_mxn": 60.00,
            "initial_stock": 100,
        },
        headers=seller_headers,
    )
    prod_id = p_resp.json()["id"]

    list_resp = await client.post(
        "/api/v1/b2b/listings",
        json={
            "product_id": prod_id,
            "wholesale_price_mxn": 70.00,
            "min_wholesale_quantity": 10,
            "available_b2b_stock": 50,
        },
        headers=seller_headers,
    )
    listing_id = list_resp.json()["id"]

    # Setup Comprador
    suffix_b = uuid.uuid4().hex[:6]
    buyer_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda La Flor {suffix_b}",
            "slug": f"tienda-flor-{suffix_b}",
            "full_name": "Comprador Flor",
            "email": f"flor_{suffix_b}@nexus.mx",
            "password": "password123",
        },
    )
    buyer_token = buyer_reg.json()["access_token"]
    buyer_headers = {"Authorization": f"Bearer {buyer_token}"}

    # Emitir pedido
    order_resp = await client.post(
        "/api/v1/b2b/orders",
        json={
            "seller_tenant_id": seller_tenant_id,
            "delivery_type": "PICKUP",
            "items": [{"b2b_listing_id": listing_id, "quantity": 12}],
        },
        headers=buyer_headers,
    )
    order_id = order_resp.json()["id"]

    # Comprador consulta sus pedidos emitidos
    sent_resp = await client.get("/api/v1/b2b/orders/sent", headers=buyer_headers)
    assert sent_resp.status_code == 200
    sent_orders = sent_resp.json()
    assert any(o["id"] == order_id for o in sent_orders)

    # Vendedor consulta sus pedidos recibidos
    rec_resp = await client.get("/api/v1/b2b/orders/received", headers=seller_headers)
    assert rec_resp.status_code == 200
    rec_orders = rec_resp.json()
    assert any(o["id"] == order_id for o in rec_orders)


@pytest.mark.asyncio
async def test_unauthorized_party_cannot_update_order_status(client: AsyncClient):
    """
    Test 10: Validación de seguridad multi-inquilino. Un comercio ajeno no puede modificar el estado de un pedido ajeno (403 Forbidden).
    """
    # Vendedor y Comprador legítimos
    suffix_s = uuid.uuid4().hex[:6]
    seller_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Vendedor Uno {suffix_s}",
            "slug": f"vendedor-uno-{suffix_s}",
            "full_name": "Vendedor Uno",
            "email": f"v1_{suffix_s}@nexus.mx",
            "password": "password123",
        },
    )
    seller_token = seller_reg.json()["access_token"]
    seller_tenant_id = seller_reg.json()["user"]["tenant_id"]
    seller_headers = {"Authorization": f"Bearer {seller_token}"}

    p_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Atún en Agua 140g {suffix_s}",
            "sku": f"ATU-140-{suffix_s}",
            "price_mxn": 22.00,
            "cost_mxn": 15.00,
            "initial_stock": 100,
        },
        headers=seller_headers,
    )
    prod_id = p_resp.json()["id"]

    list_resp = await client.post(
        "/api/v1/b2b/listings",
        json={
            "product_id": prod_id,
            "wholesale_price_mxn": 17.50,
            "min_wholesale_quantity": 24,
            "available_b2b_stock": 96,
        },
        headers=seller_headers,
    )
    listing_id = list_resp.json()["id"]

    suffix_b = uuid.uuid4().hex[:6]
    buyer_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Comprador Dos {suffix_b}",
            "slug": f"comprador-dos-{suffix_b}",
            "full_name": "Comprador Dos",
            "email": f"c2_{suffix_b}@nexus.mx",
            "password": "password123",
        },
    )
    buyer_token = buyer_reg.json()["access_token"]
    buyer_headers = {"Authorization": f"Bearer {buyer_token}"}

    order_resp = await client.post(
        "/api/v1/b2b/orders",
        json={
            "seller_tenant_id": seller_tenant_id,
            "delivery_type": "DELIVERY",
            "items": [{"b2b_listing_id": listing_id, "quantity": 24}],
        },
        headers=buyer_headers,
    )
    order_id = order_resp.json()["id"]

    # Tercer comercio ajeno
    suffix_c = uuid.uuid4().hex[:6]
    stranger_reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Comercio Extraño {suffix_c}",
            "slug": f"comercio-extrano-{suffix_c}",
            "full_name": "Invasor",
            "email": f"extrano_{suffix_c}@nexus.mx",
            "password": "password123",
        },
    )
    stranger_token = stranger_reg.json()["access_token"]
    stranger_headers = {"Authorization": f"Bearer {stranger_token}"}

    # El extraño intenta modificar el estado del pedido ajeno
    hack_resp = await client.patch(
        f"/api/v1/b2b/orders/{order_id}/status",
        json={"status": "ACCEPTED"},
        headers=stranger_headers,
    )
    assert hack_resp.status_code == 403
