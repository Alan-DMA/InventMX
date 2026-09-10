# Importación del módulo decimal para cálculos monetarios exactos
from decimal import Decimal
# Importación del módulo uuid para generar identificadores únicos
import uuid
# Importación de pytest para pruebas asíncronas
import pytest
# Importación de AsyncClient de httpx para peticiones HTTP
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_parse_receipt_bimbo_invoice_heuristics(client: AsyncClient):
    """
    Test 1: Parseo heurístico de ticket/remisión física de proveedor Bimbo (RF-28 / Const. Art. 4.2).
    Verifica detección de proveedor, folio, cantidades, costos y totales.
    """
    # 1. Registrar comercio y obtener token de autenticación
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes OCR {suffix}",
            "slug": f"ocr-test-{suffix}",
            "full_name": "Dueño OCR",
            "email": f"ocr_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Texto plano simulado extraído por Google ML Kit en Flutter
    raw_ocr_text = """
    DISTRIBUIDORA BIMBO S.A. DE C.V.
    RFC: BIM010101XYZ
    REMISION: REM-84920
    FECHA: 2026-09-10
    -------------------------------------------
    24 PZ Pan Blanco Grande $38.50 $924.00
    12 PZ Donas 6pz $21.00 $252.00
    10 PZ Medias Noches 8pz $24.00 $240.00
    -------------------------------------------
    SUBTOTAL: $1416.00
    TOTAL: $1416.00
    GRACIAS POR SU COMPRA
    """

    # 3. Invocar endpoint de parseo OCR
    ocr_payload = {
        "raw_text": raw_ocr_text,
    }
    resp = await client.post("/api/v1/purchases/parse-receipt", json=ocr_payload, headers=headers)
    assert resp.status_code == 200
    data = resp.json()

    # 4. Validar campos detectados
    assert data["supplier_name"] == "Bimbo"
    assert data["invoice_reference"] == "REM-84920"
    assert len(data["items"]) == 3
    assert Decimal(str(data["total_amount_mxn"])) == Decimal("1416.00")
    assert data["unmatched_items_count"] == 3  # Aún no existen en el catálogo

    # Validar renglón 1
    item0 = data["items"][0]
    assert "Pan Blanco Grande" in item0["detected_name"]
    assert Decimal(str(item0["detected_quantity"])) == Decimal("24.0000")
    assert Decimal(str(item0["detected_unit_cost_mxn"])) == Decimal("38.5000")
    assert Decimal(str(item0["detected_total_mxn"])) == Decimal("924.00")
    assert item0["matched_product_id"] is None


@pytest.mark.asyncio
async def test_parse_receipt_fuzzy_matching_with_catalog(client: AsyncClient):
    """
    Test 2: Cotejo difuso (fuzzy match) de renglones OCR con productos ya existentes en catálogo.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Fuzzy {suffix}",
            "slug": f"fuzzy-test-{suffix}",
            "full_name": "Dueño Fuzzy",
            "email": f"fuzzy_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Crear producto en inventario del comercio vía /api/v1/inventory/products
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Coca Cola 600ml No Retornable",
            "sku": "COC-600-NR",
            "price_mxn": 18.00,
            "cost_mxn": 14.50,
            "initial_stock": 50,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    created_product = prod_resp.json()
    product_id = created_product["id"]

    # Texto OCR con variación de texto ("COCA COLA 600ML")
    raw_ocr_text = """
    EMBOTELLADORA FEMSA COCA-COLA
    FOLIO: FAC-119283
    24 PZ COCA COLA 600ML $14.50 $348.00
    10 PZ AGUA CIEL 1L $9.00 $90.00
    """

    ocr_payload = {"raw_text": raw_ocr_text}
    resp = await client.post("/api/v1/purchases/parse-receipt", json=ocr_payload, headers=headers)
    assert resp.status_code == 200
    data = resp.json()

    assert data["supplier_name"] == "Femsa" or data["supplier_name"] == "Coca-Cola"
    assert data["invoice_reference"] == "FAC-119283"
    assert len(data["items"]) == 2

    # Verificar que el primer producto hizo match automático con el catálogo
    item_coca = data["items"][0]
    assert item_coca["matched_product_id"] == product_id
    assert item_coca["matched_product_name"] == "Coca Cola 600ml No Retornable"
    assert item_coca["matched_product_sku"] == "COC-600-NR"
    assert item_coca["confidence_score"] >= 0.55

    # El agua Ciel no existe en inventario
    item_ciel = data["items"][1]
    assert item_ciel["matched_product_id"] is None
    assert data["unmatched_items_count"] == 1


@pytest.mark.asyncio
async def test_parse_receipt_multi_tenant_isolation(client: AsyncClient):
    """
    Test 3: Aislamiento estricto multi-tenant: Los productos de un comercio A
    NO deben coincidir con las facturas OCR de un comercio B (RLS Multi-tenant).
    """
    suffix_a = uuid.uuid4().hex[:6]
    reg_a = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda A {suffix_a}",
            "slug": f"store-a-{suffix_a}",
            "full_name": "Dueño A",
            "email": f"owner_a_{suffix_a}@tienda.mx",
            "password": "password123",
        },
    )
    token_a = reg_a.json()["access_token"]
    headers_a = {"Authorization": f"Bearer {token_a}"}

    # Tienda A crea Galletas Emperador
    await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Galletas Emperador Chocolate 100g",
            "sku": "EMP-CHOC-100",
            "price_mxn": 22.00,
            "cost_mxn": 16.00,
            "initial_stock": 20,
        },
        headers=headers_a,
    )

    # Crear Tienda B (tenant distinto)
    suffix_b = uuid.uuid4().hex[:6]
    reg_b = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda B {suffix_b}",
            "slug": f"store-b-{suffix_b}",
            "full_name": "Dueño B",
            "email": f"owner_b_{suffix_b}@tienda.mx",
            "password": "password123",
        },
    )
    token_b = reg_b.json()["access_token"]
    headers_b = {"Authorization": f"Bearer {token_b}"}

    # Tienda B sube factura con Galletas Emperador
    raw_ocr_text = "10 PZ Galletas Emperador Chocolate 100g $16.00 $160.00"
    resp_b = await client.post(
        "/api/v1/purchases/parse-receipt",
        json={"raw_text": raw_ocr_text},
        headers=headers_b,
    )
    assert resp_b.status_code == 200
    data_b = resp_b.json()

    # Tienda B NO debe ver el producto de Tienda A
    assert len(data_b["items"]) == 1
    assert data_b["items"][0]["matched_product_id"] is None
    assert data_b["unmatched_items_count"] == 1


@pytest.mark.asyncio
async def test_parse_receipt_alternative_line_patterns(client: AsyncClient):
    """
    Test 4: Detección de patrones sintácticos variados de remisiones y tickets.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Sintaxis {suffix}",
            "slug": f"syntax-{suffix}",
            "full_name": "Dueño Sintaxis",
            "email": f"syntax_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Patrón 2: Sabritas Sal 45g 30 x 12.50 = 375.00
    # Patrón 3: 10 Maruchan Pollo 150.00
    # Patrón 4: Galletas Marias 20 15.50
    raw_text = """
    NOTA: 99120
    Sabritas Sal 45g 30 x 12.50 = 375.00
    10 Maruchan Pollo 150.00
    Galletas Marias 20 15.50
    """

    resp = await client.post(
        "/api/v1/purchases/parse-receipt",
        json={"raw_text": raw_text},
        headers=headers,
    )
    assert resp.status_code == 200
    data = resp.json()

    assert data["invoice_reference"] == "99120"
    assert len(data["items"]) == 3
    # 375.00 + 150.00 + (20 * 15.50 = 310.00) = 835.00
    assert Decimal(str(data["total_amount_mxn"])) == Decimal("835.00")

    # Línea 1 (Patrón 2)
    assert "Sabritas Sal 45g" in data["items"][0]["detected_name"]
    assert Decimal(str(data["items"][0]["detected_quantity"])) == Decimal("30.0000")
    assert Decimal(str(data["items"][0]["detected_unit_cost_mxn"])) == Decimal("12.5000")
    assert Decimal(str(data["items"][0]["detected_total_mxn"])) == Decimal("375.00")

    # Línea 2 (Patrón 3: 10 piezas por 150.00 -> costo unitario 15.00)
    assert "Maruchan Pollo" in data["items"][1]["detected_name"]
    assert Decimal(str(data["items"][1]["detected_quantity"])) == Decimal("10.0000")
    assert Decimal(str(data["items"][1]["detected_unit_cost_mxn"])) == Decimal("15.0000")
    assert Decimal(str(data["items"][1]["detected_total_mxn"])) == Decimal("150.00")

    # Línea 3 (Patrón 4: 20 piezas a 15.50)
    assert "Galletas Marias" in data["items"][2]["detected_name"]
    assert Decimal(str(data["items"][2]["detected_quantity"])) == Decimal("20.0000")
    assert Decimal(str(data["items"][2]["detected_unit_cost_mxn"])) == Decimal("15.5000")
    assert Decimal(str(data["items"][2]["detected_total_mxn"])) == Decimal("310.00")


@pytest.mark.asyncio
async def test_parse_voice_dictation_standard_phrase(client: AsyncClient):
    """
    Test 5: Captura Asistida por Dictado de Voz Nativo (SR-09 / Const. Art. 7.7).
    Frase común: 'Coca cola dos litros precio 38 pesos stock 24'
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Voz {suffix}",
            "slug": f"voz-{suffix}",
            "full_name": "Dueño Voz",
            "email": f"voz_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    voice_payload = {
        "voice_text": "Coca cola dos litros precio 38 pesos stock 24",
    }
    resp = await client.post("/api/v1/purchases/parse-voice-dictation", json=voice_payload, headers=headers)
    assert resp.status_code == 200
    data = resp.json()

    assert "Coca Cola" in data["name"]
    assert Decimal(str(data["price_mxn"])) == Decimal("38.00")
    assert Decimal(str(data["initial_stock"])) == Decimal("24.00")
    assert data["confidence"] >= 0.90


@pytest.mark.asyncio
async def test_parse_voice_dictation_with_cost_and_filler_words(client: AsyncClient):
    """
    Test 6: Dictado con palabras de relleno ('agrega', 'por favor'), costo y piezas.
    Frase: 'Agrega nuevo Gansito Marinela precio $22.50 costo 15.00 con 30 piezas por favor'
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Voz 2 {suffix}",
            "slug": f"voz2-{suffix}",
            "full_name": "Dueño Voz 2",
            "email": f"voz2_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    voice_payload = {
        "voice_text": "Agrega nuevo Gansito Marinela precio $22.50 costo 15.00 con 30 piezas por favor",
    }
    resp = await client.post("/api/v1/purchases/parse-voice-dictation", json=voice_payload, headers=headers)
    assert resp.status_code == 200
    data = resp.json()

    assert data["name"] == "Gansito Marinela"
    assert Decimal(str(data["price_mxn"])) == Decimal("22.50")
    assert Decimal(str(data["cost_mxn"])) == Decimal("15.00")
    assert Decimal(str(data["initial_stock"])) == Decimal("30.00")


@pytest.mark.asyncio
async def test_parse_voice_dictation_minimal_and_number_words(client: AsyncClient):
    """
    Test 7: Dictado mínimo con números en español y sin costo explícito.
    Frase: 'Jugo Del Valle mango precio veinticinco pesos stock quince'
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Voz 3 {suffix}",
            "slug": f"voz3-{suffix}",
            "full_name": "Dueño Voz 3",
            "email": f"voz3_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    voice_payload = {
        "voice_text": "Jugo Del Valle mango precio veinticinco pesos stock quince",
    }
    resp = await client.post("/api/v1/purchases/parse-voice-dictation", json=voice_payload, headers=headers)
    assert resp.status_code == 200
    data = resp.json()

    assert "Jugo Del Valle Mango" in data["name"]
    assert Decimal(str(data["price_mxn"])) == Decimal("25.00")
    assert data["cost_mxn"] is None
    assert Decimal(str(data["initial_stock"])) == Decimal("15.00")
