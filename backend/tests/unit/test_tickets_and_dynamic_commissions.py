# Importación del módulo decimal para cálculos monetarios exactos
from decimal import Decimal
# Importación del módulo uuid para generar identificadores únicos
import uuid
# Importación del framework pytest para la ejecución de pruebas asíncronas
import pytest
# Importación del cliente HTTP asíncrono de httpx
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_generate_sale_ticket_58mm_formatting(client: AsyncClient):
    """
    Test 1: Generación y formateo de Nota de Venta / Ticket Térmico en 58 mm (32 columnas) (RF-08 / Const. Art. 1.2.8).
    Verifica que el ancho de papel sea 58mm y que ninguna línea exceda los 32 caracteres monoespaciados.
    """
    suffix = uuid.uuid4().hex[:6]
    # 1. Registro de comercio y obtención de token
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Ticket 58 {suffix}",
            "slug": f"ticket-58-{suffix}",
            "full_name": "Cajero 58mm",
            "email": f"cajero58_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Crear producto en catálogo ($25.50 precio, $15.00 costo)
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Galletas Marías 170g",
            "barcode": f"7508{suffix[:8]}",
            "price_mxn": 25.50,
            "cost_mxn": 15.00,
            "initial_stock": 50.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # 3. Realizar Checkout de 2 unidades ($51.00 total)
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [
            {
                "product_id": product_id,
                "quantity": 2.0,
                "unit_price_mxn": 25.50,
                "discount_mxn": 0.0,
            }
        ],
        "discount_mxn": 0.0,
        "notes": "Venta mostrador ticket 58mm",
        "payments": [
            {
                "payment_method": "CASH_MXN",
                "amount_paid_mxn": 100.00,
            }
        ],
    }
    sale_res = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert sale_res.status_code == 201
    sale_data = sale_res.json()
    sale_id = sale_data["id"]

    # 4. Consultar Ticket en formato 58 mm
    ticket_resp = await client.get(f"/api/v1/sales/{sale_id}/ticket?width_mm=58", headers=headers)
    assert ticket_resp.status_code == 200, ticket_resp.text
    ticket = ticket_resp.json()

    # 5. Validaciones de estructura y formato
    assert ticket["folio"] == sale_data["folio"]
    assert ticket["paper_width_mm"] == 58
    assert Decimal(str(ticket["total_mxn"])) == Decimal("51.00")
    assert Decimal(str(ticket["amount_paid_mxn"])) == Decimal("100.00")
    assert Decimal(str(ticket["change_returned_mxn"])) == Decimal("49.00")
    assert len(ticket["items"]) == 1
    assert ticket["items"][0]["product_name"] == "Galletas Marías 170g"

    # 6. Validar que ninguna línea del texto monoespaciado exceda 32 columnas
    raw_lines = ticket["formatted_text"].split("\n")
    assert len(raw_lines) > 5
    for line in raw_lines:
        assert len(line) <= 32, f"La línea '{line}' excede las 32 columnas (longitud: {len(line)})"


@pytest.mark.asyncio
async def test_generate_sale_ticket_80mm_formatting(client: AsyncClient):
    """
    Test 2: Generación y formateo de Ticket Térmico en 80 mm (48 columnas) (RF-08 / Const. Art. 1.2.8).
    Verifica que el ancho de papel sea 80mm y que ninguna línea exceda los 48 caracteres.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Ferretería Ticket 80 {suffix}",
            "slug": f"ticket-80-{suffix}",
            "full_name": "Cajero 80mm",
            "email": f"cajero80_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Cinta Canela 48mm x 50m Truper",
            "barcode": f"7509{suffix[:8]}",
            "price_mxn": 38.00,
            "cost_mxn": 22.00,
            "initial_stock": 20.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [
            {
                "product_id": product_id,
                "quantity": 3.0,
                "unit_price_mxn": 38.00,
                "discount_mxn": 0.0,
            }
        ],
        "payments": [
            {
                "payment_method": "CARD_TPV",
                "amount_paid_mxn": 114.00,
                "reference_code": "AUTH-445566",
            }
        ],
    }
    sale_res = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert sale_res.status_code == 201
    sale_id = sale_res.json()["id"]

    ticket_resp = await client.get(f"/api/v1/sales/{sale_id}/ticket?width_mm=80", headers=headers)
    assert ticket_resp.status_code == 200, ticket_resp.text
    ticket = ticket_resp.json()

    assert ticket["paper_width_mm"] == 80
    assert Decimal(str(ticket["total_mxn"])) == Decimal("114.00")

    raw_lines = ticket["formatted_text"].split("\n")
    for line in raw_lines:
        assert len(line) <= 48, f"La línea '{line}' excede las 48 columnas (longitud: {len(line)})"


@pytest.mark.asyncio
async def test_ticket_settings_get_and_update(client: AsyncClient):
    """
    Test 3: Consulta y actualización de configuración de ticket del comercio (RF-08).
    Valida la personalización de nombre, RFC, dirección, pie y ancho predeterminado.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Settings {suffix}",
            "slug": f"ticket-settings-{suffix}",
            "full_name": "Dueño Tienda",
            "email": f"owner_settings_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Obtener configuración predeterminada
    get_res = await client.get("/api/v1/sales/settings/ticket", headers=headers)
    assert get_res.status_code == 200
    defaults = get_res.json()
    assert defaults["paper_width_mm"] == 58
    assert defaults["show_savings"] is True

    # 2. Actualizar configuración
    update_payload = {
        "business_name": "Minisúper El Trébol",
        "legal_name": "Abarrotes El Trébol S.A. de C.V.",
        "rfc": "ATR980112ABC",
        "address": "Av. Hidalgo 123, Centro, CDMX",
        "phone": "55-1234-5678",
        "email": "contacto@eltrebol.mx",
        "footer_message": "¡Conserve su ticket para cambios dentro de 7 días!",
        "paper_width_mm": 80,
        "show_savings": True,
        "show_cashier_name": True,
        "show_taxes": True,
    }
    put_res = await client.put("/api/v1/sales/settings/ticket", json=update_payload, headers=headers)
    assert put_res.status_code == 200, put_res.text
    updated = put_res.json()
    assert updated["business_name"] == "Minisúper El Trébol"
    assert updated["rfc"] == "ATR980112ABC"
    assert updated["paper_width_mm"] == 80
    assert updated["show_taxes"] is True


@pytest.mark.asyncio
async def test_ticket_with_split_payments_and_change_rendering(client: AsyncClient):
    """
    Test 4: Renderizado de ticket con pago mixto y cambio devuelto (RF-08, RF-13, RF-14).
    Verifica que el ticket imprima todos los métodos de pago (Efectivo y Tarjeta) y el cambio.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Mixto Ticket {suffix}",
            "slug": f"mixto-ticket-{suffix}",
            "full_name": "Cajero Mixto",
            "email": f"mixtoticket_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Bulto Cemento 50kg",
            "barcode": f"7510{suffix[:8]}",
            "price_mxn": 250.00,
            "cost_mxn": 180.00,
            "initial_stock": 10.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # Venta de 2 bultos ($500.00 total), pagado con $300 Tarjeta + $300 Efectivo -> Cambio $100
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [
            {
                "product_id": product_id,
                "quantity": 2.0,
                "unit_price_mxn": 250.00,
                "discount_mxn": 0.0,
            }
        ],
        "payments": [
            {
                "payment_method": "CARD_TPV",
                "amount_paid_mxn": 300.00,
                "reference_code": "VOUCHER-9988",
            },
            {
                "payment_method": "CASH_MXN",
                "amount_paid_mxn": 300.00,
            },
        ],
    }
    sale_res = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert sale_res.status_code == 201
    sale_id = sale_res.json()["id"]

    ticket_resp = await client.get(f"/api/v1/sales/{sale_id}/ticket", headers=headers)
    assert ticket_resp.status_code == 200
    ticket = ticket_resp.json()

    assert len(ticket["payments"]) == 2
    assert Decimal(str(ticket["amount_paid_mxn"])) == Decimal("600.00")
    assert Decimal(str(ticket["change_returned_mxn"])) == Decimal("100.00")

    formatted = ticket["formatted_text"]
    assert "CARD_TPV" in formatted
    assert "CASH_MXN" in formatted
    assert "CAMBIO ENTREGADO" in formatted


@pytest.mark.asyncio
async def test_ticket_savings_block_when_discounts_applied(client: AsyncClient):
    """
    Test 5: Bloque de ahorro del cliente en ticket al aplicar descuentos (RF-08).
    Verifica que se imprima la leyenda 'USTED AHORRÓ' cuando existen descuentos en partidas o generales.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Ahorro {suffix}",
            "slug": f"ahorro-{suffix}",
            "full_name": "Cajero Ahorro",
            "email": f"ahorro_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Detergente Líquido 3L",
            "barcode": f"7511{suffix[:8]}",
            "price_mxn": 150.00,
            "cost_mxn": 90.00,
            "initial_stock": 10.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # Venta con $20.00 de descuento en partida y $10.00 global ($120.00 a pagar, $30.00 de ahorro total)
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [
            {
                "product_id": product_id,
                "quantity": 1.0,
                "unit_price_mxn": 150.00,
                "discount_mxn": 20.00,
            }
        ],
        "discount_mxn": 10.00,
    }
    sale_res = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert sale_res.status_code == 201
    sale_id = sale_res.json()["id"]

    ticket_resp = await client.get(f"/api/v1/sales/{sale_id}/ticket", headers=headers)
    assert ticket_resp.status_code == 200
    ticket = ticket_resp.json()

    assert Decimal(str(ticket["savings_mxn"])) == Decimal("30.00")
    assert "USTED AHORRÓ" in ticket["formatted_text"]


@pytest.mark.asyncio
async def test_record_commission_percentage_of_total_sale(client: AsyncClient):
    """
    Test 6: Registro de comisión calculada como porcentaje sobre la venta total bruta (RF-10 / Const. Art. 8.2).
    Total venta: $1,000.00 MXN, Tasa: 5.00% -> Comisión: $50.00 MXN.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Comisiones {suffix}",
            "slug": f"comisiones-{suffix}",
            "full_name": "Dueño Comisiones",
            "email": f"owner_comm_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    owner_data = reg_resp.json()
    token = owner_data["access_token"]
    owner_id = owner_data["user"]["id"]
    headers = {"Authorization": f"Bearer {token}"}

    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Batería Automotriz 12V",
            "barcode": f"7512{suffix[:8]}",
            "price_mxn": 1000.00,
            "cost_mxn": 650.00,
            "initial_stock": 5.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [
            {
                "product_id": product_id,
                "quantity": 1.0,
                "unit_price_mxn": 1000.00,
            }
        ],
    }
    sale_res = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert sale_res.status_code == 201
    sale_id = sale_res.json()["id"]

    # Asentar comisión del 5% sobre total
    comm_resp = await client.post(
        f"/api/v1/sales/{sale_id}/commissions?user_id={owner_id}&commission_type=PERCENTAGE_SALE&commission_rate=5.0",
        headers=headers,
    )
    assert comm_resp.status_code == 201, comm_resp.text
    comm_data = comm_resp.json()

    assert Decimal(str(comm_data["base_amount_mxn"])) == Decimal("1000.00")
    assert Decimal(str(comm_data["commission_rate"])) == Decimal("5.00")
    assert Decimal(str(comm_data["commission_amount_mxn"])) == Decimal("50.00")
    assert comm_data["is_settled"] is False


@pytest.mark.asyncio
async def test_record_commission_percentage_of_profit(client: AsyncClient):
    """
    Test 7: Registro de comisión calculada como porcentaje sobre la utilidad bruta (RF-10 / Const. Art. 8.2).
    Precio: $1,000.00 MXN, Costo: $600.00 MXN -> Utilidad: $400.00 MXN.
    Tasa: 10.00% sobre utilidad -> Comisión: $40.00 MXN.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Utilidad Comm {suffix}",
            "slug": f"util-comm-{suffix}",
            "full_name": "Vendedor Estrella",
            "email": f"estrella_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    user_data = reg_resp.json()
    token = user_data["access_token"]
    user_id = user_data["user"]["id"]
    headers = {"Authorization": f"Bearer {token}"}

    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Juego de Llantas R15",
            "barcode": f"7513{suffix[:8]}",
            "price_mxn": 1000.00,
            "cost_mxn": 600.00,
            "initial_stock": 4.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [
            {
                "product_id": product_id,
                "quantity": 1.0,
                "unit_price_mxn": 1000.00,
            }
        ],
    }
    sale_res = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert sale_res.status_code == 201
    sale_id = sale_res.json()["id"]

    # Comisión 10% sobre utilidad
    comm_resp = await client.post(
        f"/api/v1/sales/{sale_id}/commissions?user_id={user_id}&commission_type=PERCENTAGE_PROFIT&commission_rate=10.0",
        headers=headers,
    )
    assert comm_resp.status_code == 201
    comm_data = comm_resp.json()

    assert Decimal(str(comm_data["base_amount_mxn"])) == Decimal("400.00")
    assert Decimal(str(comm_data["commission_amount_mxn"])) == Decimal("40.00")


@pytest.mark.asyncio
async def test_commissions_summary_aggregation_and_filters(client: AsyncClient):
    """
    Test 8: Reporte y consolidado ejecutivo de comisiones por periodo y empleado (RF-10 / Const. Art. 8.2).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Resumen Comm {suffix}",
            "slug": f"resumen-comm-{suffix}",
            "full_name": "Dueño Resumen",
            "email": f"resumen_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    user_data = reg_resp.json()
    token = user_data["access_token"]
    user_id = user_data["user"]["id"]
    headers = {"Authorization": f"Bearer {token}"}

    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Aceite Sintético 5W30",
            "barcode": f"7514{suffix[:8]}",
            "price_mxn": 200.00,
            "cost_mxn": 120.00,
            "initial_stock": 20.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # Crear 2 ventas de $200.00 con comisión fija de $15.00 cada una
    for _ in range(2):
        sale_res = await client.post(
            "/api/v1/sales/checkout",
            json={
                "warehouse_id": warehouse_id,
                "items": [{"product_id": product_id, "quantity": 1.0, "unit_price_mxn": 200.00}],
            },
            headers=headers,
        )
        assert sale_res.status_code == 201
        s_id = sale_res.json()["id"]

        await client.post(
            f"/api/v1/sales/{s_id}/commissions?user_id={user_id}&commission_type=FIXED_PER_SALE&commission_rate=15.0",
            headers=headers,
        )

    # Consultar resumen general
    summary_resp = await client.get("/api/v1/sales/commissions/summary", headers=headers)
    assert summary_resp.status_code == 200
    summary = summary_resp.json()

    assert Decimal(str(summary["total_commissions_mxn"])) == Decimal("30.00")
    assert summary["total_sales_count"] == 2
    assert len(summary["summaries_by_user"]) >= 1

    # Filtrar por usuario específico
    user_summary_resp = await client.get(f"/api/v1/sales/commissions/summary?user_id={user_id}", headers=headers)
    assert user_summary_resp.status_code == 200
    u_sum = user_summary_resp.json()
    assert len(u_sum["summaries_by_user"]) == 1
    assert Decimal(str(u_sum["summaries_by_user"][0]["total_commission_amount_mxn"])) == Decimal("30.00")


@pytest.mark.asyncio
async def test_rls_isolation_on_tickets_and_commissions(client: AsyncClient):
    """
    Test 9: Aislamiento estricto multi-tenant (RLS) en tickets y comisiones (Const. Art. 1.2.4).
    Verifica que el Tenant B no pueda acceder al ticket ni a las comisiones del Tenant A.
    """
    suffix_a = uuid.uuid4().hex[:6]
    suffix_b = uuid.uuid4().hex[:6]

    # Registrar Tenant A
    reg_a = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda A {suffix_a}",
            "slug": f"tienda-a-{suffix_a}",
            "full_name": "Dueño A",
            "email": f"owner_a_{suffix_a}@tienda.mx",
            "password": "password123",
        },
    )
    token_a = reg_a.json()["access_token"]
    headers_a = {"Authorization": f"Bearer {token_a}"}

    # Registrar Tenant B
    reg_b = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda B {suffix_b}",
            "slug": f"tienda-b-{suffix_b}",
            "full_name": "Dueño B",
            "email": f"owner_b_{suffix_b}@tienda.mx",
            "password": "password123",
        },
    )
    token_b = reg_b.json()["access_token"]
    headers_b = {"Authorization": f"Bearer {token_b}"}

    # Tenant A crea producto y venta
    prod_a = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Producto Exclusivo A",
            "barcode": f"7515{suffix_a[:8]}",
            "price_mxn": 100.00,
            "cost_mxn": 50.00,
            "initial_stock": 10.0,
        },
        headers=headers_a,
    )
    prod_data_a = prod_a.json()
    product_id_a = prod_data_a["id"]
    warehouse_id_a = prod_data_a["stocks"][0]["warehouse_id"]

    sale_a = await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id_a,
            "items": [{"product_id": product_id_a, "quantity": 1.0}],
        },
        headers=headers_a,
    )
    assert sale_a.status_code == 201
    sale_id_a = sale_a.json()["id"]

    # Tenant B intenta consultar el ticket de la venta del Tenant A -> Debe retornar 404
    cross_ticket_resp = await client.get(f"/api/v1/sales/{sale_id_a}/ticket", headers=headers_b)
    assert cross_ticket_resp.status_code == 404
