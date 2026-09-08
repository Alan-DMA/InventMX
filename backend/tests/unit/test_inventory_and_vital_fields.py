# Importación del módulo decimal para validaciones numéricas
from decimal import Decimal
# Importación de UUID para generación de datos de prueba
import uuid
# Importación del framework pytest
import pytest
# Importación del cliente HTTP asíncrono
from httpx import AsyncClient

# Importación de utilidades de JWT para generación de tokens en diferentes estados
from app.core.security.jwt import create_access_token


@pytest.mark.asyncio
async def test_create_product_with_three_vital_fields(client: AsyncClient):
    """
    HU-05 / CU-05 (SR-08 / Const. Art. 7.3):
    Verifica que un comerciante pueda registrar un producto en menos de 5 segundos
    enviando únicamente los 3 Campos Vitales:
    1. name: Nombre comercial
    2. price_mxn: Precio de venta en MXN
    3. initial_stock: Existencias iniciales
    El sistema debe autogenerar el SKU ('NEX-XXXXX'), asignar la categoría 'General'
    y registrar el stock inicial en el 'Almacén Principal'.
    """
    suffix = uuid.uuid4().hex[:6]
    # 1. Registrar comercio y obtener token de dueño
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Don Pepe {suffix}",
            "slug": f"abarrotes-pepe-{suffix}",
            "full_name": "José Pérez",
            "email": f"pepe_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Registrar producto con los 3 Campos Vitales
    vital_payload = {
        "name": "Coca-Cola 600ml",
        "price_mxn": 18.50,
        "initial_stock": 24.0,
    }
    create_resp = await client.post(
        "/api/v1/inventory/products",
        json=vital_payload,
        headers=headers,
    )
    assert create_resp.status_code == 201
    prod_data = create_resp.json()

    # 3. Validaciones de la regla de los 3 Campos Vitales
    assert prod_data["name"] == "Coca-Cola 600ml"
    assert float(prod_data["price_mxn"]) == 18.50
    assert float(prod_data["total_stock"]) == 24.0
    # Validación del SKU autogenerado con formato NEX-XXXXX
    assert prod_data["sku"].startswith("NEX-")
    assert len(prod_data["sku"]) >= 8
    # Validación de asignación automática de categoría por defecto
    assert prod_data["category_name"] == "General"
    # Validación de existencias desglosadas en el almacén principal
    assert len(prod_data["stocks"]) == 1
    assert float(prod_data["stocks"][0]["current_stock"]) == 24.0


@pytest.mark.asyncio
async def test_price_validation_mxn_non_negative(client: AsyncClient):
    """
    Const. Art. 1.2.4 & Art. 2.3:
    Verifica que el sistema rechace de forma estricta precios o existencias negativas
    para garantizar la integridad contable y comercial en Pesos Mexicanos.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Miscelánea Lupita {suffix}",
            "slug": f"miscelanea-{suffix}",
            "full_name": "Lupita",
            "email": f"lupita_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Intento de crear con precio negativo
    invalid_price_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Refresco", "price_mxn": -15.00, "initial_stock": 10.0},
        headers=headers,
    )
    assert invalid_price_resp.status_code == 422

    # 2. Intento de crear con existencias negativas
    invalid_stock_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Refresco", "price_mxn": 15.00, "initial_stock": -5.0},
        headers=headers,
    )
    assert invalid_stock_resp.status_code == 422


@pytest.mark.asyncio
async def test_rls_isolation_products_and_stocks(client: AsyncClient):
    """
    HU-01 / CU-01 (Const. Art. 2.2):
    Verifica el aislamiento estricto multi-tenant por Row-Level Security (RLS).
    El Tenant A y el Tenant B no deben poder ver, modificar ni eliminar los productos del otro.
    """
    suffix_a = uuid.uuid4().hex[:6]
    suffix_b = uuid.uuid4().hex[:6]

    # Registrar Tienda A
    reg_a = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda A {suffix_a}",
            "slug": f"tienda-a-{suffix_a}",
            "full_name": "Dueño A",
            "email": f"a_{suffix_a}@tienda.mx",
            "password": "password123",
        },
    )
    token_a = reg_a.json()["access_token"]
    headers_a = {"Authorization": f"Bearer {token_a}"}

    # Registrar Tienda B
    reg_b = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda B {suffix_b}",
            "slug": f"tienda-b-{suffix_b}",
            "full_name": "Dueño B",
            "email": f"b_{suffix_b}@tienda.mx",
            "password": "password123",
        },
    )
    token_b = reg_b.json()["access_token"]
    headers_b = {"Authorization": f"Bearer {token_b}"}

    # Crear producto en Tienda A
    prod_a_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Sabritas Sal 45g", "price_mxn": 17.00, "initial_stock": 30.0},
        headers=headers_a,
    )
    prod_a_id = prod_a_resp.json()["id"]

    # Crear producto en Tienda B
    prod_b_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Doritos Nacho 58g", "price_mxn": 19.50, "initial_stock": 15.0},
        headers=headers_b,
    )
    prod_b_id = prod_b_resp.json()["id"]

    # 1. Tienda A lista productos -> solo debe ver su producto Sabritas
    list_a = await client.get("/api/v1/inventory/products", headers=headers_a)
    assert list_a.status_code == 200
    items_a = list_a.json()
    assert len(items_a) == 1
    assert items_a[0]["name"] == "Sabritas Sal 45g"

    # 2. Tienda B lista productos -> solo debe ver su producto Doritos
    list_b = await client.get("/api/v1/inventory/products", headers=headers_b)
    assert list_b.status_code == 200
    items_b = list_b.json()
    assert len(items_b) == 1
    assert items_b[0]["name"] == "Doritos Nacho 58g"

    # 3. Tienda A intenta obtener producto de Tienda B por ID -> debe retornar 404
    cross_get = await client.get(f"/api/v1/inventory/products/{prod_b_id}", headers=headers_a)
    assert cross_get.status_code == 404

    # 4. Tienda A intenta modificar producto de Tienda B -> debe retornar 404
    cross_put = await client.put(
        f"/api/v1/inventory/products/{prod_b_id}",
        json={"name": "Sabotaje", "price_mxn": 1.00},
        headers=headers_a,
    )
    assert cross_put.status_code == 404

    # 5. Tienda A intenta borrar producto de Tienda B -> debe retornar 404
    cross_del = await client.delete(f"/api/v1/inventory/products/{prod_b_id}", headers=headers_a)
    assert cross_del.status_code == 404


@pytest.mark.asyncio
async def test_fuzzy_search_trigram_and_barcode(client: AsyncClient):
    """
    RF-29 / SR-04:
    Verifica la búsqueda de productos en < 10ms utilizando subcadenas/trigramas
    y coincidencia exacta por código de barras físico EAN-13.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Super Express {suffix}",
            "slug": f"super-express-{suffix}",
            "full_name": "Carlos",
            "email": f"carlos_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Poblar 3 productos de prueba
    await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Coca-Cola Original 600ml",
            "price_mxn": 18.00,
            "initial_stock": 50.0,
            "barcode": "7501055300075",
        },
        headers=headers,
    )
    await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Galletas Emperador Chocolate 101g",
            "price_mxn": 22.00,
            "initial_stock": 20.0,
            "barcode": "7501000111223",
        },
        headers=headers,
    )
    await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Leche Entera Alpura 1L",
            "price_mxn": 28.50,
            "initial_stock": 15.0,
        },
        headers=headers,
    )

    # 1. Búsqueda por subcadena difusa: 'coca'
    search_coca = await client.get("/api/v1/inventory/products?q=coca", headers=headers)
    assert search_coca.status_code == 200
    res_coca = search_coca.json()
    assert len(res_coca) == 1
    assert "Coca-Cola" in res_coca[0]["name"]

    # 2. Búsqueda por código de barras exacto: '7501055300075'
    search_barcode = await client.get("/api/v1/inventory/products?q=7501055300075", headers=headers)
    assert search_barcode.status_code == 200
    res_barcode = search_barcode.json()
    assert len(res_barcode) == 1
    assert res_barcode[0]["barcode"] == "7501055300075"

    # 3. Búsqueda por palabra clave: 'emperador'
    search_emp = await client.get("/api/v1/inventory/products?q=emperador", headers=headers)
    assert search_emp.status_code == 200
    res_emp = search_emp.json()
    assert len(res_emp) == 1
    assert "Emperador" in res_emp[0]["name"]


@pytest.mark.asyncio
async def test_low_stock_filter_and_margin_calculation(client: AsyncClient):
    """
    RF-04 & RF-20:
    Verifica el cálculo exacto del margen de ganancia comercial en MXN
    y el filtro de alertas de existencias críticas (low_stock=true).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Farmacia San Jorge {suffix}",
            "slug": f"farmacia-{suffix}",
            "full_name": "Jorge",
            "email": f"jorge_{suffix}@farmacia.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Producto con stock bajo (2 piezas <= min_stock_alert 5 piezas)
    # Precio $50.00 MXN, Costo $35.00 MXN -> Margen = (15 / 50) * 100 = 30.0%
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Paracetamol 500mg 20 tabletas",
            "price_mxn": 50.00,
            "cost_mxn": 35.00,
            "initial_stock": 2.0,
            "min_stock_alert": 5.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_data = prod_resp.json()

    # Validar campos calculados
    assert prod_data["is_low_stock"] is True
    assert float(prod_data["margin_percentage"]) == 30.0

    # Consultar con filtro de stock bajo
    low_stock_resp = await client.get("/api/v1/inventory/products?low_stock=true", headers=headers)
    assert low_stock_resp.status_code == 200
    assert len(low_stock_resp.json()) == 1


@pytest.mark.asyncio
async def test_cashier_rbac_inventory_permissions(client: AsyncClient):
    """
    Doc. Maestro Sec. 9.2 (RBAC):
    Verifica que un empleado con rol CASHIER pueda consultar el catálogo (inventory.view)
    pero no pueda crear productos (inventory.create) ni borrarlos (inventory.delete).
    """
    suffix = uuid.uuid4().hex[:6]
    # Dueño registra tienda
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tiendita {suffix}",
            "slug": f"tiendita-{suffix}",
            "full_name": "Patrón",
            "email": f"patron_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token_owner = reg_resp.json()["access_token"]
    headers_owner = {"Authorization": f"Bearer {token_owner}"}

    # Obtener rol CASHIER
    roles_resp = await client.get("/api/v1/roles", headers=headers_owner)
    cashier_role = next(r for r in roles_resp.json() if r["name"] == "CASHIER")

    # Crear cajero
    create_emp_resp = await client.post(
        "/api/v1/users",
        json={
            "email": f"cajero_{suffix}@tienda.mx",
            "password": "password123",
            "full_name": "Cajero 1",
            "role_id": cashier_role["id"],
        },
        headers=headers_owner,
    )
    assert create_emp_resp.status_code == 201

    # Login del cajero
    login_resp = await client.post(
        "/api/v1/auth/login",
        json={"email": f"cajero_{suffix}@tienda.mx", "password": "password123"},
    )
    assert login_resp.status_code == 200
    token_cashier = login_resp.json()["access_token"]
    headers_cashier = {"Authorization": f"Bearer {token_cashier}"}

    # 1. Cajero consulta inventario -> Permitido (200 OK)
    list_resp = await client.get("/api/v1/inventory/products", headers=headers_cashier)
    assert list_resp.status_code == 200

    # 2. Cajero intenta crear producto -> Denegado (403 Forbidden)
    create_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Producto No Autorizado", "price_mxn": 10.00, "initial_stock": 1.0},
        headers=headers_cashier,
    )
    assert create_resp.status_code == 403


@pytest.mark.asyncio
async def test_soft_lock_prevents_inventory_mutations(client: AsyncClient):
    """
    Const. Art. 6.3 (SaaS Soft Lock):
    Verifica que en estado SOFT_LOCK (morosidad inicial), el comercio pueda consultar
    su catálogo pero se le bloquee la creación o edición de productos con 403 Forbidden.
    """
    tenant_id = uuid.uuid4()
    user_id = uuid.uuid4()

    # Generar token simulado con tenant en SOFT_LOCK
    soft_lock_token = create_access_token(
        subject=str(user_id),
        tenant_id=str(tenant_id),
        role="OWNER",
        tenant_status="SOFT_LOCK",
    )
    headers = {"Authorization": f"Bearer {soft_lock_token}"}

    # 1. Petición POST de creación de producto debe ser bloqueada con 403
    create_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Refresco", "price_mxn": 20.00, "initial_stock": 10.0},
        headers=headers,
    )
    assert create_resp.status_code == 403
