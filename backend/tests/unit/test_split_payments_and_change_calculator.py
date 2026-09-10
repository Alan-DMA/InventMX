# Importación del módulo decimal para cálculos monetarios exactos
from decimal import Decimal
# Importación del módulo uuid para generar identificadores y nombres únicos
import uuid
# Importación del framework pytest para la ejecución de pruebas asíncronas
import pytest
# Importación del cliente HTTP asíncrono de httpx
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_single_cash_payment_exact_amount(client: AsyncClient):
    """
    Test 1: Pago exacto en efectivo sin vuelto ($100.00 pagados para total de $100.00).
    Verifica cálculo de vuelto 0.00, asignación de tipo CASH_MXN y estado COMPLETED (RF-13 / Const. Art. 3.2).
    """
    # Generación de sufijo único para el comercio
    suffix = uuid.uuid4().hex[:6]
    # Registro de nuevo tenant para la prueba
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Pago Exacto {suffix}",
            "slug": f"pago-exacto-{suffix}",
            "full_name": "Cajero Exacto",
            "email": f"exacto_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    # Verificación de registro exitoso
    assert reg_resp.status_code == 201
    # Extracción de token de autenticación
    token = reg_resp.json()["access_token"]
    # Configuración de cabeceras de autorización
    headers = {"Authorization": f"Bearer {token}"}

    # Creación de producto para la venta ($100.00 precio, $60.00 costo)
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Aceite Vegetal 1L",
            "barcode": f"7501{suffix[:8]}",
            "price_mxn": 100.00,
            "cost_mxn": 60.00,
            "initial_stock": 20.0,
        },
        headers=headers,
    )
    # Verificación de producto creado
    assert prod_resp.status_code == 201
    # Extracción de datos del producto y almacén
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # Preparación del payload de checkout con pago exacto en efectivo
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [
            {
                "product_id": product_id,
                "quantity": 1.0,
                "unit_price_mxn": 100.00,
                "discount_mxn": 0.0,
            }
        ],
        "discount_mxn": 0.0,
        "notes": "Pago exacto en efectivo",
        "payments": [
            {
                "payment_method": "CASH_MXN",
                "amount_paid_mxn": 100.00,
                "reference_code": None,
                "notes": "Efectivo exacto",
            }
        ],
    }

    # Ejecución de la petición de checkout
    response = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    # Verificación de respuesta exitosa
    assert response.status_code == 201, response.text
    # Parseo de datos devueltos
    data = response.json()
    # Verificación del estado y montos
    assert data["status"] == "COMPLETED"
    assert Decimal(str(data["total_mxn"])) == Decimal("100.00")
    assert Decimal(str(data["amount_paid_mxn"])) == Decimal("100.00")
    assert Decimal(str(data["change_returned_mxn"])) == Decimal("0.00")
    assert data["payment_method_type"] == "CASH_MXN"
    # Verificación de desglose de pagos asociados
    assert len(data["payments"]) == 1
    assert data["payments"][0]["payment_method"] == "CASH_MXN"
    assert Decimal(str(data["payments"][0]["amount_paid_mxn"])) == Decimal("100.00")


@pytest.mark.asyncio
async def test_cash_payment_with_change_calculation(client: AsyncClient):
    """
    Test 2: Pago en efectivo con vuelto ($500.00 recibidos para un total de $370.00).
    Verifica que amount_paid_mxn registre $500.00, change_returned_mxn sea $130.00 (RF-13, RF-14 / Const. Art. 3.2).
    """
    # Generación de sufijo único para el comercio
    suffix = uuid.uuid4().hex[:6]
    # Registro de nuevo tenant
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Con Vuelto {suffix}",
            "slug": f"con-vuelto-{suffix}",
            "full_name": "Cajero Vuelto",
            "email": f"vuelto_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    # Verificación de registro exitoso
    assert reg_resp.status_code == 201
    # Extracción de token y cabeceras
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Creación de producto para la venta ($185.00 precio, $120.00 costo)
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Bulto de Azúcar 5kg",
            "barcode": f"7502{suffix[:8]}",
            "price_mxn": 185.00,
            "cost_mxn": 120.00,
            "initial_stock": 10.0,
        },
        headers=headers,
    )
    # Verificación de producto creado
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # Preparación del payload de checkout: 2 unidades = $370.00, cliente entrega billete de $500
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [
            {
                "product_id": product_id,
                "quantity": 2.0,
                "unit_price_mxn": 185.00,
                "discount_mxn": 0.0,
            }
        ],
        "discount_mxn": 0.0,
        "payments": [
            {
                "payment_method": "CASH_MXN",
                "amount_paid_mxn": 500.00,
                "notes": "Billete de 500 pesos",
            }
        ],
    }

    # Ejecución de checkout
    response = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    # Verificación de estado 201
    assert response.status_code == 201, response.text
    data = response.json()
    # Validación de cálculos monetarios
    assert data["status"] == "COMPLETED"
    assert Decimal(str(data["total_mxn"])) == Decimal("370.00")
    assert Decimal(str(data["amount_paid_mxn"])) == Decimal("500.00")
    assert Decimal(str(data["change_returned_mxn"])) == Decimal("130.00")
    assert data["payment_method_type"] == "CASH_MXN"


@pytest.mark.asyncio
async def test_split_payment_cash_and_electronic_tpv(client: AsyncClient):
    """
    Test 3: Pago mixto / dividido ($200.00 en efectivo + $300.00 en tarjeta TPV para total de $500.00).
    Verifica que payment_method_type sea MULTIPLE y se almacenen ambos asientos de cobro (RF-13 / Const. Art. 3.2).
    """
    # Generación de sufijo único
    suffix = uuid.uuid4().hex[:6]
    # Registro de nuevo tenant
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Pago Mixto {suffix}",
            "slug": f"pago-mixto-{suffix}",
            "full_name": "Cajero Mixto",
            "email": f"mixto_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    # Verificación y obtención de credenciales
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Creación de producto ($250.00)
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Paquete Herramientas",
            "barcode": f"7503{suffix[:8]}",
            "price_mxn": 250.00,
            "cost_mxn": 160.00,
            "initial_stock": 5.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # Checkout de 2 unidades = $500.00, con pago mixto
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
                "payment_method": "CASH_MXN",
                "amount_paid_mxn": 200.00,
                "notes": "Efectivo parcial",
            },
            {
                "payment_method": "CARD_TPV",
                "amount_paid_mxn": 300.00,
                "reference_code": "AUTH-987654",
                "notes": "Terminal Bancaria BBVA",
            },
        ],
    }

    # Envío de la venta
    response = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert response.status_code == 201, response.text
    data = response.json()

    # Validaciones de totales y desglose
    assert data["status"] == "COMPLETED"
    assert Decimal(str(data["total_mxn"])) == Decimal("500.00")
    assert Decimal(str(data["amount_paid_mxn"])) == Decimal("500.00")
    assert Decimal(str(data["change_returned_mxn"])) == Decimal("0.00")
    assert data["payment_method_type"] == "MULTIPLE"
    assert len(data["payments"]) == 2

    # Verificación de métodos de pago en el detalle
    methods = [p["payment_method"] for p in data["payments"]]
    assert "CASH_MXN" in methods
    assert "CARD_TPV" in methods


@pytest.mark.asyncio
async def test_split_payment_with_excess_cash_change(client: AsyncClient):
    """
    Test 4: Pago mixto con exceso en efectivo ($300.00 tarjeta TPV + $300.00 efectivo para cuenta de $500.00).
    Verifica que el cambio devuelto sea $100.00 y no exceda la porción en efectivo (RF-13, RF-14).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Mixto Vuelto {suffix}",
            "slug": f"mixto-vuelto-{suffix}",
            "full_name": "Cajero Mixto Vuelto",
            "email": f"mixtovuelto_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Pintura Vinílica 4L",
            "barcode": f"7504{suffix[:8]}",
            "price_mxn": 500.00,
            "cost_mxn": 320.00,
            "initial_stock": 10.0,
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
                "unit_price_mxn": 500.00,
                "discount_mxn": 0.0,
            }
        ],
        "payments": [
            {
                "payment_method": "CARD_TPV",
                "amount_paid_mxn": 300.00,
                "reference_code": "TPV-112233",
            },
            {
                "payment_method": "CASH_MXN",
                "amount_paid_mxn": 300.00,
                "notes": "Cliente paga $300 en efectivo con billete",
            },
        ],
    }

    response = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert response.status_code == 201, response.text
    data = response.json()

    assert data["status"] == "COMPLETED"
    assert Decimal(str(data["total_mxn"])) == Decimal("500.00")
    assert Decimal(str(data["amount_paid_mxn"])) == Decimal("600.00")
    assert Decimal(str(data["change_returned_mxn"])) == Decimal("100.00")
    assert data["payment_method_type"] == "MULTIPLE"


@pytest.mark.asyncio
async def test_split_payment_insufficient_amount_without_deferred(client: AsyncClient):
    """
    Test 5: Pago insuficiente sin bandera diferida ($200.00 pagados para cuenta de $500.00).
    Verifica que el backend rechace la transacción con HTTP 400 Bad Request (RF-13 / Const. Art. 3.2).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Pago Incompleto {suffix}",
            "slug": f"incompleto-{suffix}",
            "full_name": "Cajero Control",
            "email": f"incompleto_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Taladro Percutor 1/2",
            "barcode": f"7505{suffix[:8]}",
            "price_mxn": 500.00,
            "cost_mxn": 350.00,
            "initial_stock": 5.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # Checkout con pago insuficiente y sin diferir
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [
            {
                "product_id": product_id,
                "quantity": 1.0,
                "unit_price_mxn": 500.00,
                "discount_mxn": 0.0,
            }
        ],
        "payments": [
            {
                "payment_method": "CASH_MXN",
                "amount_paid_mxn": 200.00,
            }
        ],
    }

    # Se espera error 400
    response = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert response.status_code == 400
    assert "insuficiente" in response.json()["detail"]


@pytest.mark.asyncio
async def test_deferred_payment_sale_pending_status(client: AsyncClient):
    """
    Test 6: Venta con pago diferido o a cuenta ($200.00 pagados de anticipo para $500.00).
    Verifica que la venta se registre en estado PENDING_PAYMENT (RF-18 / Const. Art. 3.2).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Credito {suffix}",
            "slug": f"credito-{suffix}",
            "full_name": "Cajero Credito",
            "email": f"credito_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Sierra Circular",
            "barcode": f"7506{suffix[:8]}",
            "price_mxn": 500.00,
            "cost_mxn": 320.00,
            "initial_stock": 8.0,
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
                "unit_price_mxn": 500.00,
                "discount_mxn": 0.0,
            }
        ],
        "allow_partial_payment": True,
        "payments": [
            {
                "payment_method": "CASH_MXN",
                "amount_paid_mxn": 200.00,
                "notes": "Anticipo 40%",
            }
        ],
    }

    response = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert response.status_code == 201, response.text
    data = response.json()

    assert data["status"] == "PENDING_PAYMENT"
    assert Decimal(str(data["total_mxn"])) == Decimal("500.00")
    assert Decimal(str(data["amount_paid_mxn"])) == Decimal("200.00")
    assert Decimal(str(data["change_returned_mxn"])) == Decimal("0.00")
    assert len(data["payments"]) == 1


@pytest.mark.asyncio
async def test_add_subsequent_payment_to_pending_sale(client: AsyncClient):
    """
    Test 7: Abono subsecuente a venta pendiente de pago ($300.00 vía SPEI a venta diferida de $500.00).
    Verifica que la venta pase a estado COMPLETED y totalice $500.00 pagados (RF-18 / Const. Art. 3.2).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Abonos {suffix}",
            "slug": f"abonos-{suffix}",
            "full_name": "Cajero Cobrador",
            "email": f"abonos_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Bicicleta de Reparto",
            "barcode": f"7507{suffix[:8]}",
            "price_mxn": 500.00,
            "cost_mxn": 300.00,
            "initial_stock": 5.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # Paso 1: Crear venta pendiente con anticipo de $200.00
    checkout_resp = await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "items": [{"product_id": product_id, "quantity": 1.0, "unit_price_mxn": 500.00}],
            "allow_partial_payment": True,
            "payments": [{"payment_method": "CASH_MXN", "amount_paid_mxn": 200.00}],
        },
        headers=headers,
    )
    assert checkout_resp.status_code == 201, checkout_resp.text
    sale_data = checkout_resp.json()
    sale_id = sale_data["id"]
    assert sale_data["status"] == "PENDING_PAYMENT"

    # Paso 2: Liquidar saldo pendiente con abono de $300.00 SPEI
    payment_resp = await client.post(
        f"/api/v1/sales/{sale_id}/payments",
        json={
            "payment_method": "SPEI",
            "amount_paid_mxn": 300.00,
            "reference_code": "SPEI-BBVA-998877",
            "notes": "Liquidación final vía transferencia",
        },
        headers=headers,
    )
    assert payment_resp.status_code == 200, payment_resp.text
    updated_sale = payment_resp.json()

    # Verificación de que la venta ahora esté completada
    assert updated_sale["status"] == "COMPLETED"
    assert Decimal(str(updated_sale["amount_paid_mxn"])) == Decimal("500.00")
    assert Decimal(str(updated_sale["change_returned_mxn"])) == Decimal("0.00")
    assert len(updated_sale["payments"]) == 2
    assert updated_sale["payment_method_type"] == "MULTIPLE"


@pytest.mark.asyncio
async def test_banxico_quick_change_calculator_endpoint(client: AsyncClient):
    """
    Test 8: Calculadora rápida de cambio Banxico (RF-14 / Const. Art. 3.2).
    Verifica cálculo algorítmico voraz de billetes y monedas mexicanas de curso legal.
    Total: $168.50, Recibido: $500.00 -> Vuelto: $331.50
    Desglose esperado:
    - 1 billete de $200
    - 1 billete de $100
    - 1 billete/moneda de $20
    - 1 moneda de $10
    - 1 moneda de $1
    - 1 moneda de $0.50 (50 centavos)
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Banxico {suffix}",
            "slug": f"banxico-{suffix}",
            "full_name": "Cajero Banxico",
            "email": f"banxico_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    payload = {
        "total_mxn": 168.50,
        "cash_received_mxn": 500.00,
    }

    resp = await client.post("/api/v1/sales/quick-change", json=payload, headers=headers)
    assert resp.status_code == 200, resp.text
    data = resp.json()

    assert Decimal(str(data["change_mxn"])) == Decimal("331.50")
    breakdown = data["banxico_breakdown"]

    # Verificación exacta de denominaciones Banxico
    assert breakdown["bills"]["200"] == 1
    assert breakdown["bills"]["100"] == 1
    assert breakdown["bills"]["20"] == 1
    assert breakdown["coins"]["10"] == 1
    assert breakdown["coins"]["1"] == 1
    assert breakdown["coins"]["0.50"] == 1
    assert "1000" not in breakdown["bills"] or breakdown["bills"].get("1000", 0) == 0
    assert "500" not in breakdown["bills"] or breakdown["bills"].get("500", 0) == 0


@pytest.mark.asyncio
async def test_banxico_quick_change_insufficient_tender_error(client: AsyncClient):
    """
    Test 9: Verificación de validación de monto recibido insuficiente en calculadora Banxico (RF-14).
    Si el monto recibido es menor al total, debe retornar error 400.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Banxico Error {suffix}",
            "slug": f"banxico-err-{suffix}",
            "full_name": "Cajero Error",
            "email": f"banxico_err_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    payload = {
        "total_mxn": 200.00,
        "cash_received_mxn": 150.00,
    }

    resp = await client.post("/api/v1/sales/quick-change", json=payload, headers=headers)
    assert resp.status_code == 400
