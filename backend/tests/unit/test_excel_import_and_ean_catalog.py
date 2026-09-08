# Importación del módulo io para buffers en memoria
import io
# Importación del módulo json para serialización de mapeos
import json
# Importación del módulo uuid para generación de datos únicos
import uuid
# Importación del framework pytest
import pytest
# Importación de openpyxl para construcción de archivos Excel en memoria
import openpyxl
# Importación del cliente HTTP asíncrono
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_seed_catalog_ean_lookup_found(client: AsyncClient):
    """
    RF-29 / Const. Art. 7.5:
    Verifica que la consulta de un código de barras oficial de México (ej. Coca-Cola 7501055300075)
    retorne instantáneamente los datos oficiales precargados en el Catálogo Semilla Maestro (Tier 1).
    """
    suffix = uuid.uuid4().hex[:6]
    # 1. Registrar comercio y obtener token
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"EAN Store {suffix}",
            "slug": f"ean-store-{suffix}",
            "full_name": "Dueño EAN",
            "email": f"ean_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Consultar código de barras oficial de Coca-Cola 600ml
    lookup_resp = await client.get(
        "/api/v1/inventory/lookup-ean/7501055300075",
        headers=headers,
    )
    assert lookup_resp.status_code == 200
    data = lookup_resp.json()
    assert data["found"] is True
    prod = data["product"]
    assert "Coca-Cola" in prod["name"]
    assert prod["brand"] == "Coca-Cola"
    assert prod["category_name"] == "Bebidas"
    assert float(prod["suggested_price_mxn"]) == 18.50


@pytest.mark.asyncio
async def test_seed_catalog_ean_lookup_not_found(client: AsyncClient):
    """
    RF-29:
    Verifica que la consulta de un código de barras inexistente retorne limpiamente found=False.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"EAN Store 2 {suffix}",
            "slug": f"ean-store-2-{suffix}",
            "full_name": "Dueño 2",
            "email": f"ean2_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Consultar código no registrado
    lookup_resp = await client.get(
        "/api/v1/inventory/lookup-ean/9999999999999",
        headers=headers,
    )
    assert lookup_resp.status_code == 200
    data = lookup_resp.json()
    assert data["found"] is False
    assert data["product"] is None


@pytest.mark.asyncio
async def test_excel_preview_endpoint(client: AsyncClient):
    """
    RF-01:
    Verifica que el endpoint de previsualización analice un archivo Excel (.xlsx),
    extraiga encabezados reales y sugiera el mapeo de columnas automáticamente.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Preview Store {suffix}",
            "slug": f"preview-store-{suffix}",
            "full_name": "Dueño Preview",
            "email": f"prev_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear archivo Excel en memoria
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.append(["DESCRIPCION_PRODUCTO", "PRECIO_VENTA", "CANTIDAD_STOCK", "FAMILIA"])
    ws.append(["Galletas Oreo 114g", "$ 22.00", 15, "Galletas"])
    ws.append(["Papas Pringles 124g", 48.50, "10", "Botanas"])
    ws.append(["Jugo del Valle Mango 413ml", 16.00, 24, "Bebidas"])

    excel_buffer = io.BytesIO()
    wb.save(excel_buffer)
    excel_buffer.seek(0)

    # 2. Enviar a /inventory/import/preview
    files = {"file": ("catalogo_proveedor.xlsx", excel_buffer.getvalue(), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")}
    prev_resp = await client.post(
        "/api/v1/inventory/import/preview",
        files=files,
        headers=headers,
    )
    assert prev_resp.status_code == 200
    preview_data = prev_resp.json()

    assert preview_data["total_detected_rows"] == 3
    assert len(preview_data["headers"]) == 4
    assert "DESCRIPCION_PRODUCTO" in preview_data["headers"]
    assert len(preview_data["sample_rows"]) == 3
    assert preview_data["suggested_mapping"]["name_column"] == "DESCRIPCION_PRODUCTO"
    assert preview_data["suggested_mapping"]["price_column"] == "PRECIO_VENTA"
    assert preview_data["suggested_mapping"]["stock_column"] == "CANTIDAD_STOCK"
    assert preview_data["suggested_mapping"]["category_column"] == "FAMILIA"


@pytest.mark.asyncio
async def test_excel_dynamic_import_with_custom_mapping(client: AsyncClient):
    """
    RF-01 / Const. Art. 7.3:
    Verifica la ingesta masiva de un archivo Excel con mapeo dinámico personalizado:
    - Limpieza de precios con signos '$'
    - Creación de categorías dinámicas
    - Inserción correcta de existencias en almacén principal
    - Respeto a los 3 Campos Vitales.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Import Store {suffix}",
            "slug": f"import-store-{suffix}",
            "full_name": "Dueño Import",
            "email": f"imp_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear archivo Excel con 4 productos y formato de precios variado
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.append(["ITEM", "COSTO_COMPRA", "PRECIO_PUBLICO", "EXISTENCIAS", "DEPARTAMENTO"])
    ws.append(["Aceite Nutrioli 850ml", "$ 32.00", "$ 45.50", "20", "Abarrotes"])
    ws.append(["Atún Tuny en Agua 140g", "14.50", "21.00", "50", "Enlatados"])
    ws.append(["Shampoo Caprice 750ml", "28.00", "39.90", "12", "Cuidado Personal"])
    ws.append(["Jabón Zote Blanco 400g", "15.00", "22.50", "30", "Limpieza"])

    excel_buffer = io.BytesIO()
    wb.save(excel_buffer)
    excel_buffer.seek(0)

    # 2. Configurar el mapeo dinámico
    mapping_payload = {
        "name_column": "ITEM",
        "price_column": "PRECIO_PUBLICO",
        "stock_column": "EXISTENCIAS",
        "cost_column": "COSTO_COMPRA",
        "category_column": "DEPARTAMENTO",
    }

    # 3. Enviar a /inventory/import/execute
    files = {"file": ("inventario_mayoreo.xlsx", excel_buffer.getvalue(), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")}
    data = {"mapping": json.dumps(mapping_payload)}

    exec_resp = await client.post(
        "/api/v1/inventory/import/execute",
        files=files,
        data=data,
        headers=headers,
    )
    assert exec_resp.status_code == 200
    result = exec_resp.json()
    assert result["total_rows"] == 4
    assert result["imported_count"] == 4
    assert result["skipped_count"] == 0
    assert result["status"] == "completed"

    # 4. Verificar consulta de catálogo
    catalog_resp = await client.get("/api/v1/inventory/products", headers=headers)
    assert catalog_resp.status_code == 200
    products = catalog_resp.json()
    assert len(products) == 4

    nutrioli = next(p for p in products if "Nutrioli" in p["name"])
    assert float(nutrioli["price_mxn"]) == 45.50
    assert float(nutrioli["cost_mxn"]) == 32.00
    assert float(nutrioli["total_stock"]) == 20.0
    assert nutrioli["category_name"] == "Abarrotes"
    assert nutrioli["sku"].startswith("NEX-")


@pytest.mark.asyncio
async def test_csv_dynamic_import_with_auto_sku_and_categories(client: AsyncClient):
    """
    RF-01 / Const. Art. 7.3:
    Verifica la importación de archivos CSV con delimitador de coma y generación automática de SKU.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"CSV Store {suffix}",
            "slug": f"csv-store-{suffix}",
            "full_name": "Dueño CSV",
            "email": f"csv_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear contenido CSV
    csv_content = (
        "Articulo,Precio,Stock,Categoria\n"
        "Cereal Zucaritas 600g,64.00,10,Cereales\n"
        "Café Legal 200g,42.50,15,Abarrotes\n"
        "Azúcar Estándar 1kg,28.00,40,Abarrotes\n"
    )

    mapping_payload = {
        "name_column": "Articulo",
        "price_column": "Precio",
        "stock_column": "Stock",
        "category_column": "Categoria",
    }

    # 2. Enviar a /inventory/import/execute
    files = {"file": ("productos.csv", csv_content.encode("utf-8"), "text/csv")}
    data = {"mapping": json.dumps(mapping_payload)}

    exec_resp = await client.post(
        "/api/v1/inventory/import/execute",
        files=files,
        data=data,
        headers=headers,
    )
    assert exec_resp.status_code == 200
    result = exec_resp.json()
    assert result["imported_count"] == 3
    assert result["skipped_count"] == 0


@pytest.mark.asyncio
async def test_import_creates_initial_kardex_movements(client: AsyncClient):
    """
    RF-05 / Const. Art. 7.1:
    Verifica que cada producto importado con existencias iniciales > 0 registre
    su asiento contable inmutable de ADJUSTMENT_IN en el Kardex.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Kardex Import {suffix}",
            "slug": f"kardex-imp-{suffix}",
            "full_name": "Auditor",
            "email": f"kardeximp_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    csv_content = (
        "Nombre,Precio,Stock\n"
        "Suavitel 850ml,26.00,18\n"
    )
    mapping = {"name_column": "Nombre", "price_column": "Precio", "stock_column": "Stock"}
    files = {"file": ("lote1.csv", csv_content.encode("utf-8"), "text/csv")}
    data = {"mapping": json.dumps(mapping)}

    await client.post("/api/v1/inventory/import/execute", files=files, data=data, headers=headers)

    # Consultar Kardex
    kardex_resp = await client.get("/api/v1/inventory/movements", headers=headers)
    assert kardex_resp.status_code == 200
    movements = kardex_resp.json()
    assert len(movements) == 1
    m = movements[0]
    assert m["movement_type"] == "ADJUSTMENT_IN"
    assert float(m["quantity"]) == 18.0
    assert "lote1.csv" in m["notes"]


@pytest.mark.asyncio
async def test_multi_tenant_rls_during_excel_import(client: AsyncClient):
    """
    Const. Art. 4.1 & RLS:
    Verifica que la importación masiva en Tenant A esté totalmente aislada
    por PostgreSQL RLS y sea invisible para Tenant B.
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
            "email": f"a_{suffix_a}@tienda.mx",
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
            "email": f"b_{suffix_b}@tienda.mx",
            "password": "password123",
        },
    )
    token_b = reg_b.json()["access_token"]
    headers_b = {"Authorization": f"Bearer {token_b}"}

    # Tenant A importa productos
    csv_a = "Nombre,Precio,Stock\nProducto Exclusivo A,120.00,10\n"
    files = {"file": ("a.csv", csv_a.encode("utf-8"), "text/csv")}
    data = {"mapping": json.dumps({"name_column": "Nombre", "price_column": "Precio", "stock_column": "Stock"})}
    await client.post("/api/v1/inventory/import/execute", files=files, data=data, headers=headers_a)

    # Tenant B consulta productos y movimientos
    prods_b = await client.get("/api/v1/inventory/products", headers=headers_b)
    assert prods_b.status_code == 200
    assert len(prods_b.json()) == 0

    kardex_b = await client.get("/api/v1/inventory/movements", headers=headers_b)
    assert kardex_b.status_code == 200
    assert len(kardex_b.json()) == 0
