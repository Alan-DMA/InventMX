# Importación del módulo decimal para precisión en cálculos financieros
from decimal import Decimal
# Importación de UUID para identificadores únicos
import uuid
# Importación del framework de pruebas pytest
import pytest
# Importación del cliente HTTP asíncrono
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_standard_pos_checkout_with_stock_deduction_and_kardex(client: AsyncClient):
    """
    HU-11 / CU-11 (RF-09, RF-12 / Const. Art. 1.2.2 & 7.1):
    Valida el flujo de checkout estándar en mostrador:
    - Descuento de stock en almacén.
    - Generación de folio único correlativo (VTA-YYYYMMDD-XXXX).
    - Congelamiento de costo unitario y precio en MXN.
    - Registro inmutable del asiento en Kardex (SALE_EXIT).
    """
    suffix = uuid.uuid4().hex[:6]
    # 1. Registrar comercio y obtener token
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tiendita POS {suffix}",
            "slug": f"tiendita-pos-{suffix}",
            "full_name": "Don Pepe Cajero",
            "email": f"cajero_{suffix}@tiendita.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Crear Producto con existencias iniciales (20 piezas a $18.50 precio, $12.00 costo)
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Coca-Cola 600ml NR",
            "barcode": "7501055300075",
            "price_mxn": 18.50,
            "cost_mxn": 12.00,
            "initial_stock": 20.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # 3. Enviar Checkout de 2 unidades
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [
            {
                "product_id": product_id,
                "quantity": 2.0,
                "unit_price_mxn": 18.50,
                "discount_mxn": 0.0,
            }
        ],
        "discount_mxn": 0.0,
        "notes": "Venta mostrador cliente habitual",
    }
    response = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)

    # 4. Aserciones de Respuesta
    assert response.status_code == 201, response.text
    data = response.json()
    assert data["folio"].startswith("VTA-")
    assert data["status"] == "COMPLETED"
    assert Decimal(str(data["subtotal_mxn"])) == Decimal("37.00")
    assert Decimal(str(data["total_mxn"])) == Decimal("37.00")
    assert Decimal(str(data["total_cost_mxn"])) == Decimal("24.00")
    assert Decimal(str(data["gross_profit_mxn"])) == Decimal("13.00")
    assert len(data["items"]) == 1
    assert data["items"][0]["product_name"] == "Coca-Cola 600ml NR"
    assert Decimal(str(data["items"][0]["profit_mxn"])) == Decimal("13.00")

    # 5. Validar Descuento de Stock en Catálogo (20 - 2 = 18)
    p_get = await client.get(f"/api/v1/inventory/products/{product_id}", headers=headers)
    assert p_get.status_code == 200
    assert float(p_get.json()["total_stock"]) == 18.0

    # 6. Validar Asiento inmutable en Kardex
    mov_resp = await client.get(f"/api/v1/inventory/movements?product_id={product_id}", headers=headers)
    assert mov_resp.status_code == 200
    movements = mov_resp.json()
    sale_movs = [m for m in movements if m["movement_type"] == "SALE_EXIT"]
    assert len(sale_movs) == 1
    asiento = sale_movs[0]
    assert float(asiento["quantity"]) == -2.0
    assert float(asiento["previous_stock"]) == 20.0
    assert float(asiento["new_stock"]) == 18.0
    assert float(asiento["unit_cost_mxn"]) == 12.00


@pytest.mark.asyncio
async def test_historical_cost_freezing_and_profit_calculation(client: AsyncClient):
    """
    RF-20 / Const. Art. 2.3:
    Verifica que al vender un producto, el costo unitario se congele históricamente.
    Si el catálogo actualiza posteriormente el costo del producto, la venta conserva
    el costo y margen histórico real inalterado.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Costos {suffix}",
            "slug": f"costos-{suffix}",
            "full_name": "Dueño Costos",
            "email": f"costos_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Crear producto con costo $30 y precio $45
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Aceite Nutrioli 1L",
            "price_mxn": 45.00,
            "cost_mxn": 30.00,
            "initial_stock": 10.0,
        },
        headers=headers,
    )
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # Cobrar 1 unidad
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [{"product_id": product_id, "quantity": 1.0, "unit_price_mxn": 45.00}],
    }
    res_checkout = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert res_checkout.status_code == 201
    sale_id = res_checkout.json()["id"]

    # Simular que semanas después el proveedor sube el costo a $40 MXN en el catálogo
    put_resp = await client.put(
        f"/api/v1/inventory/products/{product_id}",
        json={
            "name": "Aceite Nutrioli 1L",
            "price_mxn": 55.00,
            "cost_mxn": 40.00,
        },
        headers=headers,
    )
    assert put_resp.status_code == 200

    # Consultar la venta realizada previamente
    res_get = await client.get(f"/api/v1/sales/{sale_id}", headers=headers)
    assert res_get.status_code == 200
    data = res_get.json()
    # El costo histórico de la venta previa debe seguir congelado en $30.00 y la ganancia en $15.00
    assert Decimal(str(data["total_cost_mxn"])) == Decimal("30.00")
    assert Decimal(str(data["gross_profit_mxn"])) == Decimal("15.00")
    assert Decimal(str(data["items"][0]["unit_cost_mxn"])) == Decimal("30.00")
    assert Decimal(str(data["items"][0]["profit_mxn"])) == Decimal("15.00")


@pytest.mark.asyncio
async def test_lazy_loading_organic_product_creation_on_the_fly(client: AsyncClient):
    """
    HU-11 / CU-11 (RF-09 / Const. Art. 7.3):
    Valida la creación de productos al vuelo (Lazy Loading / Inventario Orgánico):
    - Cajero escanea o digita producto no catalogado con is_on_the_fly: true.
    - Se cobra sin fricción.
    - El backend genera automáticamente el SKU 'NEX-XXXXX' y categoría 'General'.
    - Crea el producto y stock silenciosamente para ventas futuras.
    - Asienta entrada y salida en el Kardex.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda JIT {suffix}",
            "slug": f"jit-{suffix}",
            "full_name": "Cajero Rápido",
            "email": f"jit_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Crear almacén principal explícitamente
    wh_resp = await client.post(
        "/api/v1/inventory/warehouses",
        json={"name": "Matriz Centro", "is_default": True},
        headers=headers,
    )
    assert wh_resp.status_code == 201
    warehouse_id = wh_resp.json()["id"]

    # Cobrar producto no catalogado al vuelo
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [
            {
                "is_on_the_fly": True,
                "on_the_fly_name": "Chicles Trident Menta 18s",
                "on_the_fly_barcode": "7501000123456",
                "on_the_fly_cost_mxn": 8.00,
                "unit_price_mxn": 14.00,
                "quantity": 1.0,
            }
        ],
        "notes": "Producto registrado al vuelo durante fila rápida",
    }
    res = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)

    assert res.status_code == 201, res.text
    data = res.json()
    assert data["status"] == "COMPLETED"
    assert Decimal(str(data["total_mxn"])) == Decimal("14.00")
    assert Decimal(str(data["gross_profit_mxn"])) == Decimal("6.00")
    assert data["items"][0]["is_on_the_fly"] is True
    assert data["items"][0]["product_name"] == "Chicles Trident Menta 18s"
    assert data["items"][0]["product_sku"].startswith("NEX-")
    created_product_id = data["items"][0]["product_id"]

    # Validar que el producto quedó creado en el catálogo del comercio
    p_get = await client.get(f"/api/v1/inventory/products/{created_product_id}", headers=headers)
    assert p_get.status_code == 200
    p_data = p_get.json()
    assert p_data["name"] == "Chicles Trident Menta 18s"
    assert p_data["sku"].startswith("NEX-")
    assert float(p_data["price_mxn"]) == 14.00
    assert float(p_data["cost_mxn"]) == 8.00

    # Validar los asientos de Kardex generados
    mov_resp = await client.get(f"/api/v1/inventory/movements?product_id={created_product_id}", headers=headers)
    assert mov_resp.status_code == 200
    movs = mov_resp.json()
    assert len(movs) == 2
    types = [m["movement_type"] for m in movs]
    assert "ADJUSTMENT_IN" in types
    assert "SALE_EXIT" in types


@pytest.mark.asyncio
async def test_combo_checkout_deducts_all_components_stock(client: AsyncClient):
    """
    RF-03, RF-12 / Const. Art. 7.1:
    Valida que al vender un Combo o paquete promocional en el POS:
    - Se descuente automáticamente el stock de cada uno de sus componentes individuales.
    - Se generen asientos individuales en el Kardex para cada componente.
    - Se calcule la utilidad del combo con base en los costos de los componentes.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Combos {suffix}",
            "slug": f"combos-{suffix}",
            "full_name": "Admin Combos",
            "email": f"combos_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Componente 1: Pan Bimbo (Stock 10, costo 35, precio 45)
    pan_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Pan Blanco Bimbo", "price_mxn": 45.00, "cost_mxn": 35.00, "initial_stock": 10.0},
        headers=headers,
    )
    pan_data = pan_resp.json()
    pan_id = pan_data["id"]
    warehouse_id = pan_data["stocks"][0]["warehouse_id"]

    # Componente 2: Mermelada McCormick (Stock 10, costo 20, precio 30)
    merm_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Mermelada Fresa 250g", "price_mxn": 30.00, "cost_mxn": 20.00, "initial_stock": 10.0},
        headers=headers,
    )
    merm_id = merm_resp.json()["id"]

    # Crear Combo "Desayuno Dulce" por $65 MXN (Costo total = 35 + 20 = $55)
    combo_resp = await client.post(
        "/api/v1/inventory/combos",
        json={
            "name": "Combo Desayuno Dulce",
            "price_mxn": 65.00,
            "items": [
                {"product_id": pan_id, "quantity": 1.0},
                {"product_id": merm_id, "quantity": 1.0},
            ],
        },
        headers=headers,
    )
    assert combo_resp.status_code == 201
    combo_id = combo_resp.json()["id"]

    # Vender 2 combos en caja
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [{"combo_id": combo_id, "quantity": 2.0, "unit_price_mxn": 65.00}],
    }
    res = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)

    assert res.status_code == 201, res.text
    data = res.json()
    assert Decimal(str(data["total_mxn"])) == Decimal("130.00")
    # Costo = (35 + 20) * 2 = 110.00 -> Utilidad = 130 - 110 = 20.00
    assert Decimal(str(data["total_cost_mxn"])) == Decimal("110.00")
    assert Decimal(str(data["gross_profit_mxn"])) == Decimal("20.00")

    # Validar existencias resultantes en ambos componentes (10 - 2 = 8)
    pan_get = await client.get(f"/api/v1/inventory/products/{pan_id}", headers=headers)
    merm_get = await client.get(f"/api/v1/inventory/products/{merm_id}", headers=headers)
    assert float(pan_get.json()["total_stock"]) == 8.0
    assert float(merm_get.json()["total_stock"]) == 8.0


@pytest.mark.asyncio
async def test_insufficient_stock_rejection_at_checkout(client: AsyncClient):
    """
    Const. Art. 1.2.2 (ACID):
    Valida que si se intenta cobrar una cantidad mayor al stock disponible,
    la transacción se aborte de inmediato con 400 Bad Request y no se modifiquen existencias.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Stock {suffix}",
            "slug": f"stk-{suffix}",
            "full_name": "Admin Stock",
            "email": f"stk_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Crear producto con stock 3
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Arroz 1kg", "price_mxn": 28.00, "cost_mxn": 20.00, "initial_stock": 3.0},
        headers=headers,
    )
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # Intentar vender 5 unidades
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [{"product_id": product_id, "quantity": 5.0, "unit_price_mxn": 28.00}],
    }
    res = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)

    assert res.status_code == 400
    assert "Stock insuficiente" in res.json()["detail"]

    # Validar que el stock sigue intacto en 3.0
    p_get = await client.get(f"/api/v1/inventory/products/{product_id}", headers=headers)
    assert float(p_get.json()["total_stock"]) == 3.0


@pytest.mark.asyncio
async def test_sale_cancellation_reverses_stock_and_logs_kardex(client: AsyncClient):
    """
    RF-12 / Const. Art. 7.1:
    Valida la anulación de una venta:
    - Estado de la venta transiciona a CANCELLED.
    - El stock vendido se reincorpora al almacén.
    - Se registra el asiento inmutable compensatorio SALE_CANCEL en el Kardex.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Cancel {suffix}",
            "slug": f"can-{suffix}",
            "full_name": "Admin Cancel",
            "email": f"can_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear producto con 15 piezas
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Cloro 1L", "price_mxn": 18.00, "cost_mxn": 11.00, "initial_stock": 15.0},
        headers=headers,
    )
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # 2. Realizar venta de 4 unidades (Stock pasa a 11)
    checkout_payload = {
        "warehouse_id": warehouse_id,
        "items": [{"product_id": product_id, "quantity": 4.0, "unit_price_mxn": 18.00}],
    }
    res_checkout = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=headers)
    assert res_checkout.status_code == 201
    sale_id = res_checkout.json()["id"]

    # Validar que el stock bajó a 11
    p_before = await client.get(f"/api/v1/inventory/products/{product_id}", headers=headers)
    assert float(p_before.json()["total_stock"]) == 11.0

    # 3. Cancelar la venta
    cancel_payload = {"reason": "El cliente devolvió el producto en mostrador"}
    res_cancel = await client.post(f"/api/v1/sales/{sale_id}/cancel", json=cancel_payload, headers=headers)

    assert res_cancel.status_code == 200, res_cancel.text
    assert res_cancel.json()["status"] == "CANCELLED"

    # 4. Validar reversión de stock a 15
    p_after = await client.get(f"/api/v1/inventory/products/{product_id}", headers=headers)
    assert float(p_after.json()["total_stock"]) == 15.0

    # 5. Validar asiento compensatorio en Kardex
    mov_resp = await client.get(f"/api/v1/inventory/movements?product_id={product_id}", headers=headers)
    assert mov_resp.status_code == 200
    cancel_movs = [m for m in mov_resp.json() if m["movement_type"] == "SALE_CANCEL"]
    assert len(cancel_movs) == 1
    asiento = cancel_movs[0]
    assert float(asiento["quantity"]) == 4.0
    assert float(asiento["previous_stock"]) == 11.0
    assert float(asiento["new_stock"]) == 15.0


@pytest.mark.asyncio
async def test_multi_tenant_rls_isolation_on_sales(client: AsyncClient):
    """
    Const. Art. 1.2.3 (Multi-tenant RLS):
    Valida que el Tenant B no pueda consultar ni cancelar notas de venta del Tenant A.
    """
    suffix_a = uuid.uuid4().hex[:6]
    suffix_b = uuid.uuid4().hex[:6]

    # Registrar Tenant A
    reg_a = await client.post(
        "/api/v1/auth/register",
        json={"store_name": f"Store A {suffix_a}", "slug": f"store-a-{suffix_a}", "full_name": "Owner A", "email": f"a_{suffix_a}@t.mx", "password": "password123"},
    )
    token_a = reg_a.json()["access_token"]
    headers_a = {"Authorization": f"Bearer {token_a}"}

    # Registrar Tenant B
    reg_b = await client.post(
        "/api/v1/auth/register",
        json={"store_name": f"Store B {suffix_b}", "slug": f"store-b-{suffix_b}", "full_name": "Owner B", "email": f"b_{suffix_b}@t.mx", "password": "password123"},
    )
    token_b = reg_b.json()["access_token"]
    headers_b = {"Authorization": f"Bearer {token_b}"}

    # Tenant A crea producto y venta
    prod_resp_a = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Prod A", "price_mxn": 20.00, "cost_mxn": 10.00, "initial_stock": 10.0},
        headers=headers_a,
    )
    prod_data_a = prod_resp_a.json()
    prod_a = prod_data_a["id"]
    wh_a = prod_data_a["stocks"][0]["warehouse_id"]

    res_sale_a = await client.post(
        "/api/v1/sales/checkout",
        json={"warehouse_id": wh_a, "items": [{"product_id": prod_a, "quantity": 1.0, "unit_price_mxn": 20.00}]},
        headers=headers_a,
    )
    sale_a_id = res_sale_a.json()["id"]

    # Tenant B intenta consultar venta de Tenant A -> 404
    res_b_get = await client.get(f"/api/v1/sales/{sale_a_id}", headers=headers_b)
    assert res_b_get.status_code == 404

    # Tenant B intenta cancelar venta de Tenant A -> 404
    res_b_cancel = await client.post(f"/api/v1/sales/{sale_a_id}/cancel", json={"reason": "Hack"}, headers=headers_b)
    assert res_b_cancel.status_code == 404


@pytest.mark.asyncio
async def test_cashier_rbac_permissions_on_sales(client: AsyncClient):
    """
    Const. Art. 9.2 (RBAC):
    Valida que un usuario con rol CASHIER tenga permiso para checkout (sales.checkout)
    y consulta (sales.view), pero NO tenga permiso para cancelar ventas (sales.cancel),
    retornando 403 Forbidden al intentar cancelar sin permiso.
    """
    suffix = uuid.uuid4().hex[:6]
    # 1. Registrar comercio como Dueño
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={"store_name": f"Tienda RBAC {suffix}", "slug": f"rbac-{suffix}", "full_name": "Dueño Tienda", "email": f"owner_{suffix}@t.mx", "password": "password123"},
    )
    owner_token = reg_resp.json()["access_token"]
    owner_headers = {"Authorization": f"Bearer {owner_token}"}

    # 2. Dueño crea producto
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Galletas Marías", "price_mxn": 17.00, "cost_mxn": 10.00, "initial_stock": 10.0},
        headers=owner_headers,
    )
    prod_data = prod_resp.json()
    prod_id = prod_data["id"]
    wh_id = prod_data["stocks"][0]["warehouse_id"]

    # 3. Dueño obtiene ID del rol CASHIER y crea empleado
    roles_resp = await client.get("/api/v1/roles", headers=owner_headers)
    assert roles_resp.status_code == 200
    cashier_role_id = [r["id"] for r in roles_resp.json() if r["name"] == "CASHIER"][0]

    emp_resp = await client.post(
        "/api/v1/users",
        json={
            "full_name": "Cajero Juan",
            "email": f"cajero_{suffix}@t.mx",
            "password": "cajeropassword123",
            "role_id": cashier_role_id,
        },
        headers=owner_headers,
    )
    assert emp_resp.status_code == 201

    # 4. Login como Cajero
    login_resp = await client.post(
        "/api/v1/auth/login",
        json={"email": f"cajero_{suffix}@t.mx", "password": "cajeropassword123"},
    )
    assert login_resp.status_code == 200
    cashier_token = login_resp.json()["access_token"]
    cashier_headers = {"Authorization": f"Bearer {cashier_token}"}

    # 5. Cajero ejecuta checkout con éxito (tiene sales.checkout)
    checkout_payload = {"warehouse_id": wh_id, "items": [{"product_id": prod_id, "quantity": 1.0, "unit_price_mxn": 17.00}]}
    res_checkout = await client.post("/api/v1/sales/checkout", json=checkout_payload, headers=cashier_headers)
    assert res_checkout.status_code == 201
    sale_id = res_checkout.json()["id"]

    # 6. Cajero consulta venta con éxito (tiene sales.view)
    res_view = await client.get(f"/api/v1/sales/{sale_id}", headers=cashier_headers)
    assert res_view.status_code == 200

    # 7. Cajero intenta cancelar venta -> Denegado con 403 Forbidden (no tiene sales.cancel)
    res_cancel = await client.post(f"/api/v1/sales/{sale_id}/cancel", json={"reason": "Cancelación no autorizada"}, headers=cashier_headers)
    assert res_cancel.status_code == 403
    assert "sales.cancel" in res_cancel.json()["error"]["message"]
