# Importación del módulo decimal para cálculos monetarios exactos
from decimal import Decimal
# Importación del módulo datetime
from datetime import datetime, timedelta
# Importación del módulo uuid para identificadores únicos
import uuid
# Importación de pytest para pruebas asíncronas
import pytest
# Importación de AsyncClient de httpx para peticiones HTTP
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_executive_financial_summary_cogs_and_profit_margin(client: AsyncClient):
    """
    Test 1: Cálculo exacto de Ventas Netas, COGS histórico, Utilidad Bruta y Margen % (RF-18 / Const. Art. 7.6).
    """
    # 1. Registrar comercio
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Supermercado Analítica {suffix}",
            "slug": f"super-analitica-{suffix}",
            "full_name": "Dueño Finanzas",
            "email": f"finanzas_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Crear dos productos con costo y precio definidos
    p1_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Aceite Premium 1L {suffix}",
            "sku": f"ACE-1L-{suffix}",
            "price_mxn": 100.00,
            "cost_mxn": 60.00,
            "initial_stock": 50,
        },
        headers=headers,
    )
    assert p1_resp.status_code == 201
    p1_data = p1_resp.json()
    p1_id = p1_data["id"]
    warehouse_id = p1_data["stocks"][0]["warehouse_id"]

    p2_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Arroz Extra 1kg {suffix}",
            "sku": f"ARR-1K-{suffix}",
            "price_mxn": 50.00,
            "cost_mxn": 30.00,
            "initial_stock": 50,
        },
        headers=headers,
    )
    assert p2_resp.status_code == 201
    p2_id = p2_resp.json()["id"]

    # 3. Abrir turno de caja
    shift_resp = await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 500.00},
        headers=headers,
    )
    assert shift_resp.status_code == 201

    # 4. Procesar Venta 1: 2 unidades de Aceite ($200 MXN, Costo $120 MXN, Utilidad $80 MXN) en Efectivo
    sale1_resp = await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "items": [{"product_id": p1_id, "quantity": 2, "unit_price_mxn": 100.00}],
            "payments": [{"payment_method": "CASH_MXN", "amount_paid_mxn": 200.00}],
            "discount_mxn": 0.00,
        },
        headers=headers,
    )
    assert sale1_resp.status_code == 201

    # 5. Procesar Venta 2: 1 unidad de Arroz ($50 MXN, Costo $30 MXN, Utilidad $20 MXN) en Tarjeta
    sale2_resp = await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "items": [{"product_id": p2_id, "quantity": 1, "unit_price_mxn": 50.00}],
            "payments": [{"payment_method": "CARD_TPV", "amount_paid_mxn": 50.00}],
            "discount_mxn": 0.00,
        },
        headers=headers,
    )
    assert sale2_resp.status_code == 201

    # 6. Consultar resumen financiero ejecutivo
    fin_resp = await client.get("/api/v1/analytics/financial-summary?preset=TODAY", headers=headers)
    assert fin_resp.status_code == 200
    data = fin_resp.json()

    # 7. Validaciones matemáticas exactas
    assert Decimal(str(data["gross_sales_mxn"])) == Decimal("250.00")
    assert Decimal(str(data["net_sales_mxn"])) == Decimal("250.00")
    assert Decimal(str(data["cogs_mxn"])) == Decimal("150.00")
    assert Decimal(str(data["gross_profit_mxn"])) == Decimal("100.00")
    # Margen = 100 / 250 * 100 = 40.00%
    assert Decimal(str(data["profit_margin_pct"])) == Decimal("40.00")
    assert data["total_transactions"] == 2
    # Ticket promedio = 250 / 2 = 125.00
    assert Decimal(str(data["average_ticket_mxn"])) == Decimal("125.00")

    # Validar desglose por método de pago
    assert len(data["payment_methods"]) == 2
    cash_method = next(m for m in data["payment_methods"] if m["payment_method"] == "CASH_MXN")
    assert Decimal(str(cash_method["total_mxn"])) == Decimal("200.00")
    assert Decimal(str(cash_method["percentage"])) == Decimal("80.00")

    card_method = next(m for m in data["payment_methods"] if m["payment_method"] == "CARD_TPV")
    assert Decimal(str(card_method["total_mxn"])) == Decimal("50.00")
    assert Decimal(str(card_method["percentage"])) == Decimal("20.00")


@pytest.mark.asyncio
async def test_cash_flow_summary_reconciliation(client: AsyncClient):
    """
    Test 2: Conciliación de flujo de caja real (entradas vs salidas operativas) (RF-19).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Flujo Tienda {suffix}",
            "slug": f"flujo-tienda-{suffix}",
            "full_name": "Tesorero Don Pedro",
            "email": f"tesorero_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Abrir turno de caja
    shift_resp = await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 1000.00},
        headers=headers,
    )
    shift_id = shift_resp.json()["id"]

    # Crear producto y venta en efectivo
    p_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Leche 1L {suffix}",
            "sku": f"LEC-1L-{suffix}",
            "price_mxn": 28.00,
            "cost_mxn": 20.00,
            "initial_stock": 20,
        },
        headers=headers,
    )
    p_data = p_resp.json()
    p_id = p_data["id"]
    warehouse_id = p_data["stocks"][0]["warehouse_id"]

    # Venta de contado en efectivo: 5 unidades * $28 = $140 MXN
    await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "items": [{"product_id": p_id, "quantity": 5, "unit_price_mxn": 28.00}],
            "payments": [{"payment_method": "CASH_MXN", "amount_paid_mxn": 140.00}],
        },
        headers=headers,
    )

    # Registrar ingreso extra a caja (CASH_IN): $300 MXN
    await client.post(
        f"/api/v1/sales/shifts/{shift_id}/movements",
        json={
            "movement_type": "CASH_IN",
            "amount_mxn": 300.00,
            "reason": "Cambio adicional de banco",
        },
        headers=headers,
    )

    # Registrar retiro/gasto de caja (CASH_OUT): $80 MXN
    await client.post(
        f"/api/v1/sales/shifts/{shift_id}/movements",
        json={
            "movement_type": "CASH_OUT",
            "amount_mxn": 80.00,
            "reason": "Pago de garrafones de agua",
        },
        headers=headers,
    )

    # Consultar flujo de caja
    cf_resp = await client.get("/api/v1/analytics/cash-flow?preset=TODAY", headers=headers)
    assert cf_resp.status_code == 200
    cf_data = cf_resp.json()

    # Validar entradas: 140 (venta) + 300 (movimiento) = 440.00
    assert Decimal(str(cf_data["cash_sales_inflow_mxn"])) == Decimal("140.00")
    assert Decimal(str(cf_data["cash_income_movements_mxn"])) == Decimal("300.00")
    assert Decimal(str(cf_data["total_inflow_mxn"])) == Decimal("440.00")

    # Validar salidas: 80.00
    assert Decimal(str(cf_data["cash_expense_movements_mxn"])) == Decimal("80.00")
    assert Decimal(str(cf_data["total_outflow_mxn"])) == Decimal("80.00")

    # Balance neto: 440.00 - 80.00 = 360.00
    assert Decimal(str(cf_data["net_cash_flow_mxn"])) == Decimal("360.00")


@pytest.mark.asyncio
async def test_inventory_valuation_and_health_metrics(client: AsyncClient):
    """
    Test 3: Valuación del inventario físico, Top 10 ventas y stock crítico (RF-20).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Almacén Central {suffix}",
            "slug": f"almacen-central-{suffix}",
            "full_name": "Jefe Almacén",
            "email": f"almacen_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Producto 1: Alta rotación
    p1 = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Refresco Cola 600ml {suffix}",
            "sku": f"REF-600-{suffix}",
            "price_mxn": 18.00,
            "cost_mxn": 12.00,
            "initial_stock": 100,
        },
        headers=headers,
    )
    p1_data = p1.json()
    p1_id = p1_data["id"]
    warehouse_id = p1_data["stocks"][0]["warehouse_id"]

    # Producto 2: Stock crítico / Umbral bajo
    p2 = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Batería AA 4pk {suffix}",
            "sku": f"BAT-AA-{suffix}",
            "price_mxn": 65.00,
            "cost_mxn": 40.00,
            "initial_stock": 2,
            "min_stock_alert": 5,
        },
        headers=headers,
    )
    p2_id = p2.json()["id"]

    # Abrir caja y vender 15 unidades de Producto 1
    await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 200.00},
        headers=headers,
    )
    await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "items": [{"product_id": p1_id, "quantity": 15, "unit_price_mxn": 18.00}],
            "payments": [{"payment_method": "CASH_MXN", "amount_paid_mxn": 270.00}],
        },
        headers=headers,
    )

    # Consultar diagnóstico de inventario
    inv_resp = await client.get("/api/v1/analytics/inventory-health?preset=TODAY", headers=headers)
    assert inv_resp.status_code == 200
    inv_data = inv_resp.json()

    # Valuación:
    # Stock p1 = 85 unidades, costo 12 = 1020. Venta 18 = 1530.
    # Stock p2 = 2 unidades, costo 40 = 80. Venta 65 = 130.
    # Total unidades = 87. Costo total = 1100.00. Venta total = 1660.00. Ganancia potencial = 560.00.
    val = inv_data["valuation"]
    assert val["total_active_skus"] >= 2
    assert Decimal(str(val["total_units_in_stock"])) == Decimal("87.00")
    assert Decimal(str(val["total_inventory_cost_mxn"])) == Decimal("1100.00")
    assert Decimal(str(val["total_inventory_retail_mxn"])) == Decimal("1660.00")
    assert Decimal(str(val["potential_gross_profit_mxn"])) == Decimal("560.00")

    # Top vendidos: Producto 1 debe ser el #1 con 15 unidades vendidas
    top = inv_data["top_selling_products"]
    assert len(top) >= 1
    assert top[0]["product_id"] == p1_id
    assert Decimal(str(top[0]["units_sold"])) == Decimal("15.00")
    assert Decimal(str(top[0]["revenue_mxn"])) == Decimal("270.00")
    # Utilidad = 15 * (18 - 12) = 90.00
    assert Decimal(str(top[0]["profit_mxn"])) == Decimal("90.00")

    # Stock crítico: Producto 2 debe estar en la lista porque stock (2) <= min_stock (5)
    crit = inv_data["critical_stock_products"]
    assert any(c["product_id"] == p2_id for c in crit)


@pytest.mark.asyncio
async def test_working_capital_and_liquidity_position(client: AsyncClient):
    """
    Test 4: Diagnóstico de Capital de Trabajo y Liquidez Neta (RF-21).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Capital Liquidez {suffix}",
            "slug": f"capital-liq-{suffix}",
            "full_name": "Administrador Liquidez",
            "email": f"liq_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Abrir caja con $1,500 MXN
    await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 1500.00},
        headers=headers,
    )

    # 2. Crear cliente y otorgarle crédito (cuenta por cobrar = $400 MXN)
    cust_resp = await client.post(
        "/api/v1/customers",
        json={
            "full_name": f"Cliente Frecuente {suffix}",
            "phone": "5512345678",
            "credit_limit_mxn": 1000.00,
        },
        headers=headers,
    )
    cust_id = cust_resp.json()["id"]

    # Crear producto y venta a crédito (fiado)
    p_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Bulto Maíz {suffix}",
            "sku": f"MAI-50K-{suffix}",
            "price_mxn": 400.00,
            "cost_mxn": 300.00,
            "initial_stock": 10,
        },
        headers=headers,
    )
    p_data = p_resp.json()
    p_id = p_data["id"]
    warehouse_id = p_data["stocks"][0]["warehouse_id"]

    await client.post(
        "/api/v1/sales/checkout",
        json={
            "client_id": cust_id,
            "warehouse_id": warehouse_id,
            "allow_partial_payment": True,
            "items": [{"product_id": p_id, "quantity": 1.0, "unit_price_mxn": 400.00}],
            "payments": [],
            "notes": "Venta a crédito en mostrador",
        },
        headers=headers,
    )

    # 3. Crear proveedor y compra a crédito (cuenta por pagar = $600 MXN)
    sup_resp = await client.post(
        "/api/v1/suppliers",
        json={
            "name": f"Distribuidora Granos {suffix}",
            "credit_days": 15,
            "credit_limit_mxn": 5000.00,
        },
        headers=headers,
    )
    sup_id = sup_resp.json()["id"]

    po_resp = await client.post(
        "/api/v1/purchase-orders",
        json={
            "supplier_id": sup_id,
            "items": [
                {
                    "product_id": p_id,
                    "quantity_ordered": 2,
                    "unit_cost_mxn": 300.00,
                }
            ],
        },
        headers=headers,
    )
    po_data = po_resp.json()
    po_id = po_data["id"]
    po_item_id = po_data["items"][0]["id"]

    # Recepción de la orden de compra a crédito (genera cuenta por pagar por $600 MXN)
    rec_resp = await client.post(
        f"/api/v1/purchase-orders/{po_id}/receive",
        json={
            "items_received": [
                {
                    "purchase_order_item_id": po_item_id,
                    "quantity_received": 2,
                    "unit_cost_mxn": 300.00,
                }
            ]
        },
        headers=headers,
    )
    assert rec_resp.status_code == 200

    # 4. Consultar balance de capital de trabajo
    wc_resp = await client.get("/api/v1/analytics/working-capital", headers=headers)
    assert wc_resp.status_code == 200
    wc_data = wc_resp.json()

    # Caja: $1,500.00
    assert Decimal(str(wc_data["cash_in_register_mxn"])) == Decimal("1500.00")
    # Cuentas por pagar: $600.00
    assert Decimal(str(wc_data["accounts_payable_mxn"])) == Decimal("600.00")


@pytest.mark.asyncio
async def test_date_range_preset_filtering_and_custom_dates(client: AsyncClient):
    """
    Test 5: Validación de filtros temporales por presets (THIS_MONTH, THIS_WEEK, TODAY) y fechas personalizadas.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Fechas {suffix}",
            "slug": f"tienda-fechas-{suffix}",
            "full_name": "Dueño Fechas",
            "email": f"fechas_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Preset THIS_MONTH
    m_resp = await client.get("/api/v1/analytics/financial-summary?preset=THIS_MONTH", headers=headers)
    assert m_resp.status_code == 200

    # Preset THIS_WEEK
    w_resp = await client.get("/api/v1/analytics/financial-summary?preset=THIS_WEEK", headers=headers)
    assert w_resp.status_code == 200

    # Preset CUSTOM con fechas explícitas
    now = datetime.now()
    start_str = (now - timedelta(days=7)).isoformat()
    end_str = now.isoformat()
    c_resp = await client.get(
        f"/api/v1/analytics/financial-summary?preset=CUSTOM&start_date={start_str}&end_date={end_str}",
        headers=headers,
    )
    assert c_resp.status_code == 200


@pytest.mark.asyncio
async def test_analytics_multi_tenant_isolation(client: AsyncClient):
    """
    Test 6: Aislamiento multi-inquilino estricto. Las métricas financieras de la Tienda A no se filtran a la Tienda B.
    """
    # Tienda A con ventas
    suffix_a = uuid.uuid4().hex[:6]
    reg_a = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Alfa {suffix_a}",
            "slug": f"tienda-alfa-{suffix_a}",
            "full_name": "Dueño Alfa",
            "email": f"alfa_{suffix_a}@nexus.mx",
            "password": "password123",
        },
    )
    token_a = reg_a.json()["access_token"]
    headers_a = {"Authorization": f"Bearer {token_a}"}

    p_a = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Producto Alfa {suffix_a}",
            "sku": f"ALF-1-{suffix_a}",
            "price_mxn": 500.00,
            "cost_mxn": 300.00,
            "initial_stock": 10,
        },
        headers=headers_a,
    )
    p_a_data = p_a.json()
    p_a_id = p_a_data["id"]
    warehouse_a_id = p_a_data["stocks"][0]["warehouse_id"]

    await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 100.00},
        headers=headers_a,
    )
    await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_a_id,
            "items": [{"product_id": p_a_id, "quantity": 2, "unit_price_mxn": 500.00}],
            "payments": [{"payment_method": "CASH_MXN", "amount_paid_mxn": 1000.00}],
        },
        headers=headers_a,
    )

    # Tienda B sin ventas
    suffix_b = uuid.uuid4().hex[:6]
    reg_b = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Beta {suffix_b}",
            "slug": f"tienda-beta-{suffix_b}",
            "full_name": "Dueño Beta",
            "email": f"beta_{suffix_b}@nexus.mx",
            "password": "password123",
        },
    )
    token_b = reg_b.json()["access_token"]
    headers_b = {"Authorization": f"Bearer {token_b}"}

    # Tienda B consulta sus métricas
    fin_b = await client.get("/api/v1/analytics/financial-summary?preset=TODAY", headers=headers_b)
    assert fin_b.status_code == 200
    data_b = fin_b.json()

    # Tienda B debe tener $0.00 en todas las métricas
    assert Decimal(str(data_b["gross_sales_mxn"])) == Decimal("0.00")
    assert Decimal(str(data_b["net_sales_mxn"])) == Decimal("0.00")
    assert Decimal(str(data_b["cogs_mxn"])) == Decimal("0.00")
    assert Decimal(str(data_b["gross_profit_mxn"])) == Decimal("0.00")
    assert Decimal(str(data_b["profit_margin_pct"])) == Decimal("0.00")
    assert data_b["total_transactions"] == 0


@pytest.mark.asyncio
async def test_empty_analytics_safe_zero_division(client: AsyncClient):
    """
    Test 7: Comercio nuevo sin transacciones no arroja excepciones de división entre cero.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Nueva {suffix}",
            "slug": f"tienda-nueva-{suffix}",
            "full_name": "Nuevo Usuario",
            "email": f"nuevo_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    fin_resp = await client.get("/api/v1/analytics/financial-summary?preset=TODAY", headers=headers)
    assert fin_resp.status_code == 200
    data = fin_resp.json()
    assert Decimal(str(data["net_sales_mxn"])) == Decimal("0.00")
    assert Decimal(str(data["profit_margin_pct"])) == Decimal("0.00")
    assert Decimal(str(data["average_ticket_mxn"])) == Decimal("0.00")
    assert data["total_transactions"] == 0
