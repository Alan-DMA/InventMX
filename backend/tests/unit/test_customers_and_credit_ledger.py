# Importación del módulo decimal para cálculos monetarios exactos
from decimal import Decimal
# Importación del módulo uuid para generar identificadores únicos
import uuid
# Importación de pytest
import pytest
# Importación de AsyncClient de httpx
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_create_customer_with_credit_limit(client: AsyncClient):
    """
    Test 1: Registro de un nuevo cliente con línea de crédito en MXN (RF-06 / Const. Art. 1.2.6).
    Verifica que el cliente se cree con saldo deudor en $0.00 y crédito disponible igual al límite.
    """
    suffix = uuid.uuid4().hex[:6]
    # 1. Registro de comercio y obtención de token
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Don Ramón {suffix}",
            "slug": f"don-ramon-{suffix}",
            "full_name": "Propietario Don Ramón",
            "email": f"owner_ramon_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Registrar cliente con límite de $1,500.00 MXN y 15 días de plazo
    customer_payload = {
        "full_name": "Don Ramón Valdés",
        "phone": "5551234567",
        "email": "ramon.valdes@vecindad.mx",
        "address": "Calle de la Vecindad #72",
        "rfc": "VARD700101XYZ",
        "credit_limit_mxn": 1500.00,
        "credit_days": 15,
        "notes": "Cliente cumplidor de fiado",
    }
    create_res = await client.post("/api/v1/customers", json=customer_payload, headers=headers)
    assert create_res.status_code == 201
    c_data = create_res.json()
    assert c_data["full_name"] == "Don Ramón Valdés"
    assert Decimal(str(c_data["credit_limit_mxn"])) == Decimal("1500.00")
    assert Decimal(str(c_data["credit_balance_mxn"])) == Decimal("0.00")
    assert Decimal(str(c_data["available_credit_mxn"])) == Decimal("1500.00")
    assert c_data["credit_days"] == 15
    assert c_data["is_active"] is True


@pytest.mark.asyncio
async def test_list_and_search_customers(client: AsyncClient):
    """
    Test 2: Búsqueda y filtrado de clientes en mostrador por nombre/teléfono/RFC y saldo deudor.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Búsqueda {suffix}",
            "slug": f"search-cust-{suffix}",
            "full_name": "Cajero Búsqueda",
            "email": f"search_c_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Crear 3 clientes
    await client.post(
        "/api/v1/customers",
        json={"full_name": "María Elena García", "phone": "5511112222", "rfc": "MAGA800101AAA"},
        headers=headers,
    )
    await client.post(
        "/api/v1/customers",
        json={"full_name": "Juan Carlos Pérez", "phone": "5533334444", "rfc": "PEJC850505BBB"},
        headers=headers,
    )
    await client.post(
        "/api/v1/customers",
        json={"full_name": "María José López", "phone": "5555556666", "rfc": "LOJM900909CCC"},
        headers=headers,
    )

    # 1. Búsqueda por "maría" -> debe retornar 2 clientes
    search_res = await client.get("/api/v1/customers?q=maría", headers=headers)
    assert search_res.status_code == 200
    results = search_res.json()
    assert len(results) == 2
    names = [c["full_name"] for c in results]
    assert "María Elena García" in names
    assert "María José López" in names

    # 2. Búsqueda por teléfono "5533334444" -> debe retornar 1
    phone_res = await client.get("/api/v1/customers?q=5533334444", headers=headers)
    assert phone_res.status_code == 200
    assert len(phone_res.json()) == 1
    assert phone_res.json()[0]["full_name"] == "Juan Carlos Pérez"

    # 3. Filtro por clientes con deuda -> debe retornar 0
    debt_res = await client.get("/api/v1/customers?has_debt=true", headers=headers)
    assert debt_res.status_code == 200
    assert len(debt_res.json()) == 0


@pytest.mark.asyncio
async def test_update_customer_credit_limit(client: AsyncClient):
    """
    Test 3: Actualización de límite de crédito y datos de contacto de un cliente.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Update {suffix}",
            "slug": f"update-cust-{suffix}",
            "full_name": "Cajero Update",
            "email": f"update_c_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Crear cliente inicial
    c_res = await client.post(
        "/api/v1/customers",
        json={"full_name": "Doña Florinda", "credit_limit_mxn": 500.00, "credit_days": 7},
        headers=headers,
    )
    customer_id = c_res.json()["id"]

    # Actualizar límite a $2,500.00 y 30 días
    up_res = await client.put(
        f"/api/v1/customers/{customer_id}",
        json={"credit_limit_mxn": 2500.00, "credit_days": 30, "phone": "5599887766"},
        headers=headers,
    )
    assert up_res.status_code == 200
    up_data = up_res.json()
    assert Decimal(str(up_data["credit_limit_mxn"])) == Decimal("2500.00")
    assert Decimal(str(up_data["available_credit_mxn"])) == Decimal("2500.00")
    assert up_data["credit_days"] == 30
    assert up_data["phone"] == "5599887766"


@pytest.mark.asyncio
async def test_credit_sale_within_limit_success(client: AsyncClient):
    """
    Test 4: Venta a crédito en POS dentro del límite autorizado (RF-15 / Const. Art. 7.2).
    Verifica que el saldo deudor del cliente se incremente y se registre el asiento de CARGO en el libro mayor.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Fiado {suffix}",
            "slug": f"fiado-sale-{suffix}",
            "full_name": "Cajero Fiado",
            "email": f"fiado_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear cliente con crédito de $1,000.00
    c_res = await client.post(
        "/api/v1/customers",
        json={"full_name": "Señor Barriga", "credit_limit_mxn": 1000.00, "credit_days": 30},
        headers=headers,
    )
    customer_id = c_res.json()["id"]

    # 2. Crear producto ($150.00)
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Bolsa de Arroz 1kg",
            "barcode": f"7505{suffix[:8]}",
            "price_mxn": 150.00,
            "cost_mxn": 100.00,
            "initial_stock": 20.0,
        },
        headers=headers,
    )
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # 3. Realizar venta de 2 piezas ($300.00 total) a crédito sin abono inicial
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "client_id": customer_id,
        "allow_partial_payment": True,
        "items": [
            {
                "product_id": product_id,
                "quantity": 2.0,
                "unit_price_mxn": 150.00,
            }
        ],
        "payments": [],
        "notes": "Venta a crédito en mostrador",
    }
    sale_res = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert sale_res.status_code == 201
    sale_data = sale_res.json()
    assert sale_data["status"] == "PENDING_PAYMENT"
    assert Decimal(str(sale_data["total_mxn"])) == Decimal("300.00")
    assert Decimal(str(sale_data["amount_paid_mxn"])) == Decimal("0.00")

    # 4. Verificar que el cliente ahora tenga saldo deudor de $300.00 y crédito disponible de $700.00
    get_c = await client.get(f"/api/v1/customers/{customer_id}", headers=headers)
    assert get_c.status_code == 200
    c_updated = get_c.json()
    assert Decimal(str(c_updated["credit_balance_mxn"])) == Decimal("300.00")
    assert Decimal(str(c_updated["available_credit_mxn"])) == Decimal("700.00")

    # 5. Verificar estado de cuenta
    stmt_res = await client.get(f"/api/v1/customers/{customer_id}/statement", headers=headers)
    assert stmt_res.status_code == 200
    stmt_data = stmt_res.json()
    assert len(stmt_data["entries"]) == 1
    assert stmt_data["entries"][0]["entry_type"] == "CHARGE"
    assert Decimal(str(stmt_data["entries"][0]["amount_mxn"])) == Decimal("300.00")
    assert Decimal(str(stmt_data["entries"][0]["resulting_balance_mxn"])) == Decimal("300.00")


@pytest.mark.asyncio
async def test_credit_sale_exceeds_limit_rejection(client: AsyncClient):
    """
    Test 5: Rechazo transaccional de venta a crédito que excede la línea disponible (HTTP 422).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Rechazo {suffix}",
            "slug": f"rechazo-sale-{suffix}",
            "full_name": "Cajero Rechazo",
            "email": f"rechazo_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear cliente con crédito de solo $500.00
    c_res = await client.post(
        "/api/v1/customers",
        json={"full_name": "Quico Villagrán", "credit_limit_mxn": 500.00, "credit_days": 15},
        headers=headers,
    )
    customer_id = c_res.json()["id"]

    # 2. Crear producto caro ($800.00)
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Bicicleta Infantil",
            "barcode": f"7506{suffix[:8]}",
            "price_mxn": 800.00,
            "cost_mxn": 500.00,
            "initial_stock": 5.0,
        },
        headers=headers,
    )
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # 3. Intentar checkout a crédito de $800.00 -> Debe fallar con HTTP 422
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "client_id": customer_id,
        "allow_partial_payment": True,
        "items": [
            {
                "product_id": product_id,
                "quantity": 1.0,
                "unit_price_mxn": 800.00,
            }
        ],
        "payments": [],
    }
    fail_res = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert fail_res.status_code == 422
    assert "excede la línea disponible" in fail_res.json()["detail"]


@pytest.mark.asyncio
async def test_record_customer_credit_payment_partial(client: AsyncClient):
    """
    Test 6: Registro de abono parcial que disminuye el saldo deudor del cliente (RF-15).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Abono {suffix}",
            "slug": f"abono-sale-{suffix}",
            "full_name": "Cajero Abono",
            "email": f"abono_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear cliente con crédito $2,000.00
    c_res = await client.post(
        "/api/v1/customers",
        json={"full_name": "Profesor Jirafales", "credit_limit_mxn": 2000.00},
        headers=headers,
    )
    customer_id = c_res.json()["id"]

    # 2. Crear producto ($400.00) y vender 2 piezas = $800.00 de deuda
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Ramo de Rosas",
            "barcode": f"7507{suffix[:8]}",
            "price_mxn": 400.00,
            "cost_mxn": 200.00,
            "initial_stock": 10.0,
        },
        headers=headers,
    )
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "client_id": customer_id,
            "allow_partial_payment": True,
            "items": [{"product_id": product_id, "quantity": 2.0, "unit_price_mxn": 400.00}],
            "payments": [],
        },
        headers=headers,
    )

    # 3. Registrar abono de $300.00 en Efectivo
    pay_res = await client.post(
        f"/api/v1/customers/{customer_id}/payments",
        json={
            "amount_mxn": 300.00,
            "payment_method": "CASH_MXN",
            "notes": "Abono quincenal",
        },
        headers=headers,
    )
    assert pay_res.status_code == 201
    p_data = pay_res.json()
    assert Decimal(str(p_data["amount_paid_mxn"])) == Decimal("300.00")
    assert Decimal(str(p_data["previous_balance_mxn"])) == Decimal("800.00")
    assert Decimal(str(p_data["resulting_balance_mxn"])) == Decimal("500.00")
    assert Decimal(str(p_data["available_credit_mxn"])) == Decimal("1500.00")

    # 4. Verificar saldo del cliente
    c_check = await client.get(f"/api/v1/customers/{customer_id}", headers=headers)
    assert Decimal(str(c_check.json()["credit_balance_mxn"])) == Decimal("500.00")


@pytest.mark.asyncio
async def test_record_customer_credit_payment_full_settlement(client: AsyncClient):
    """
    Test 7: Liquidación total de la cuenta del cliente dejando saldo en $0.00.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Liquidacion {suffix}",
            "slug": f"liq-sale-{suffix}",
            "full_name": "Cajero Liquidacion",
            "email": f"liq_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Crear cliente
    c_res = await client.post(
        "/api/v1/customers",
        json={"full_name": "Doña Clotilde", "credit_limit_mxn": 1000.00},
        headers=headers,
    )
    customer_id = c_res.json()["id"]

    # Venta de $350.00
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Pastel de Chocolate",
            "barcode": f"7508{suffix[:8]}",
            "price_mxn": 350.00,
            "cost_mxn": 200.00,
            "initial_stock": 5.0,
        },
        headers=headers,
    )
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "client_id": customer_id,
            "allow_partial_payment": True,
            "items": [{"product_id": product_id, "quantity": 1.0, "unit_price_mxn": 350.00}],
            "payments": [],
        },
        headers=headers,
    )

    # Liquidación con Transferencia SPEI de $350.00
    pay_res = await client.post(
        f"/api/v1/customers/{customer_id}/payments",
        json={
            "amount_mxn": 350.00,
            "payment_method": "SPEI",
            "reference_code": "SPEI-77665544",
            "notes": "Pago total por transferencia",
        },
        headers=headers,
    )
    assert pay_res.status_code == 201
    p_data = pay_res.json()
    assert Decimal(str(p_data["resulting_balance_mxn"])) == Decimal("0.00")
    assert Decimal(str(p_data["available_credit_mxn"])) == Decimal("1000.00")


@pytest.mark.asyncio
async def test_customer_statement_and_ledger_chronology(client: AsyncClient):
    """
    Test 8: Consulta de estado de cuenta con múltiples cargos y abonos en secuencia cronológica.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Estado Cuenta {suffix}",
            "slug": f"statement-{suffix}",
            "full_name": "Cajero Estado Cuenta",
            "email": f"stmt_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Crear cliente con $5,000 de límite
    c_res = await client.post(
        "/api/v1/customers",
        json={"full_name": "Godínez", "credit_limit_mxn": 5000.00},
        headers=headers,
    )
    customer_id = c_res.json()["id"]

    # Crear producto
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Cuaderno Profesional",
            "barcode": f"7509{suffix[:8]}",
            "price_mxn": 100.00,
            "cost_mxn": 50.00,
            "initial_stock": 50.0,
        },
        headers=headers,
    )
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # 1. Cargo 1: 5 piezas = $500.00
    await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "client_id": customer_id,
            "allow_partial_payment": True,
            "items": [{"product_id": product_id, "quantity": 5.0, "unit_price_mxn": 100.00}],
            "payments": [],
        },
        headers=headers,
    )

    # 2. Abono 1: $200.00
    await client.post(
        f"/api/v1/customers/{customer_id}/payments",
        json={"amount_mxn": 200.00, "payment_method": "CASH_MXN"},
        headers=headers,
    )

    # 3. Cargo 2: 3 piezas = $300.00
    await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "client_id": customer_id,
            "allow_partial_payment": True,
            "items": [{"product_id": product_id, "quantity": 3.0, "unit_price_mxn": 100.00}],
            "payments": [],
        },
        headers=headers,
    )

    # Consultar estado de cuenta
    stmt_res = await client.get(f"/api/v1/customers/{customer_id}/statement", headers=headers)
    assert stmt_res.status_code == 200
    stmt_data = stmt_res.json()
    # Total Cargos: $500 + $300 = $800.00
    assert Decimal(str(stmt_data["total_charges_mxn"])) == Decimal("800.00")
    # Total Abonos: $200.00
    assert Decimal(str(stmt_data["total_payments_mxn"])) == Decimal("200.00")
    # Saldo Actual: $600.00
    assert Decimal(str(stmt_data["credit_balance_mxn"])) == Decimal("600.00")
    # Crédito Disponible: $5,000 - $600 = $4,400.00
    assert Decimal(str(stmt_data["available_credit_mxn"])) == Decimal("4400.00")
    assert len(stmt_data["entries"]) == 3


@pytest.mark.asyncio
async def test_customers_multi_tenant_rls_isolation(client: AsyncClient):
    """
    Test 9: Verificación de aislamiento estricto multi-inquilino (RLS) en catálogo de clientes y créditos.
    """
    suffix_a = uuid.uuid4().hex[:6]
    suffix_b = uuid.uuid4().hex[:6]

    # Inquilino A
    reg_a = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda A {suffix_a}",
            "slug": f"tenant-a-{suffix_a}",
            "full_name": "Dueño A",
            "email": f"owner_a_{suffix_a}@tienda.mx",
            "password": "password123",
        },
    )
    token_a = reg_a.json()["access_token"]
    headers_a = {"Authorization": f"Bearer {token_a}"}

    # Inquilino B
    reg_b = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda B {suffix_b}",
            "slug": f"tenant-b-{suffix_b}",
            "full_name": "Dueño B",
            "email": f"owner_b_{suffix_b}@tienda.mx",
            "password": "password123",
        },
    )
    token_b = reg_b.json()["access_token"]
    headers_b = {"Authorization": f"Bearer {token_b}"}

    # Inquilino A crea cliente
    create_a = await client.post(
        "/api/v1/customers",
        json={"full_name": "Cliente Exclusivo A", "credit_limit_mxn": 1000.00},
        headers=headers_a,
    )
    customer_a_id = create_a.json()["id"]

    # Inquilino B intenta consultar cliente de A -> debe recibir HTTP 404
    get_b = await client.get(f"/api/v1/customers/{customer_a_id}", headers=headers_b)
    assert get_b.status_code == 404

    # Inquilino B lista clientes -> debe recibir lista vacía
    list_b = await client.get("/api/v1/customers", headers=headers_b)
    assert list_b.status_code == 200
    assert len(list_b.json()) == 0
