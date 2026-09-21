# Importación del módulo decimal para cálculos monetarios exactos
from datetime import date, timedelta
from decimal import Decimal
# Importación del módulo uuid para generar identificadores únicos
import uuid
# Importación de pytest
import pytest
# Importación de AsyncClient de httpx
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_create_supplier_with_credit_terms(client: AsyncClient):
    """
    Test 1: Registro de un nuevo proveedor con términos comerciales y línea de crédito en MXN (RF-15).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes El Triunfo {suffix}",
            "slug": f"triunfo-supp-{suffix}",
            "full_name": "Dueño El Triunfo",
            "email": f"owner_triunfo_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Registrar proveedor nacional
    supplier_payload = {
        "name": "Distribuidora Bimbo S.A. de C.V.",
        "rfc": "BIM010101XYZ",
        "phone": "5558889900",
        "email": "pedidos@bimbo.com.mx",
        "address": "Av. Insurgentes Sur #1000, CDMX",
        "credit_days": 15,
        "credit_limit_mxn": 25000.00,
        "notes": "Entrega los días martes y viernes",
    }
    create_res = await client.post("/api/v1/suppliers", json=supplier_payload, headers=headers)
    assert create_res.status_code == 201
    data = create_res.json()
    assert data["name"] == "Distribuidora Bimbo S.A. de C.V."
    assert data["rfc"] == "BIM010101XYZ"
    assert data["credit_days"] == 15
    assert Decimal(str(data["credit_limit_mxn"])) == Decimal("25000.00")
    assert data["status"] == "ACTIVE"


@pytest.mark.asyncio
async def test_list_and_search_suppliers(client: AsyncClient):
    """
    Test 2: Búsqueda y filtrado de proveedores por nombre o RFC.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Búsqueda Prov {suffix}",
            "slug": f"search-supp-{suffix}",
            "full_name": "Dueño Búsqueda",
            "email": f"search_supp_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Crear 3 proveedores
    await client.post("/api/v1/suppliers", json={"name": "Coca-Cola FEMSA", "rfc": "FEM700101AAA"}, headers=headers)
    await client.post("/api/v1/suppliers", json={"name": "Grupo Bimbo", "rfc": "BIM700101BBB"}, headers=headers)
    await client.post("/api/v1/suppliers", json={"name": "Sabritas PepsiCo", "rfc": "SAB700101CCC"}, headers=headers)

    # Buscar "Bimbo"
    res_search = await client.get("/api/v1/suppliers?search=Bimbo", headers=headers)
    assert res_search.status_code == 200
    items = res_search.json()
    assert len(items) == 1
    assert "Bimbo" in items[0]["name"]

    # Listar todos
    res_all = await client.get("/api/v1/suppliers", headers=headers)
    assert res_all.status_code == 200
    assert len(res_all.json()) >= 3


@pytest.mark.asyncio
async def test_update_and_deactivate_supplier(client: AsyncClient):
    """
    Test 3: Actualización de datos comerciales y desactivación de proveedor.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Mutación {suffix}",
            "slug": f"mutate-supp-{suffix}",
            "full_name": "Dueño Mutación",
            "email": f"mutate_supp_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    create_res = await client.post(
        "/api/v1/suppliers",
        json={"name": "Lácteos Santa Clara", "credit_days": 7, "credit_limit_mxn": 5000.00},
        headers=headers,
    )
    supp_id = create_res.json()["id"]

    # Modificar días de crédito y teléfono
    put_res = await client.put(
        f"/api/v1/suppliers/{supp_id}",
        json={"credit_days": 14, "phone": "5551122334", "credit_limit_mxn": 8000.00},
        headers=headers,
    )
    assert put_res.status_code == 200
    assert put_res.json()["credit_days"] == 14
    assert put_res.json()["phone"] == "5551122334"
    assert Decimal(str(put_res.json()["credit_limit_mxn"])) == Decimal("8000.00")

    # Desactivar proveedor
    del_res = await client.delete(f"/api/v1/suppliers/{supp_id}", headers=headers)
    assert del_res.status_code == 200
    assert del_res.json()["status"] == "INACTIVE"


@pytest.mark.asyncio
async def test_create_purchase_order_with_items(client: AsyncClient):
    """
    Test 4: Creación de una orden de compra con múltiples productos y cálculo en MXN (RF-15).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Supermercado La Fe {suffix}",
            "slug": f"la-fe-{suffix}",
            "full_name": "Dueño La Fe",
            "email": f"owner_lafe_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear proveedor
    supp_res = await client.post(
        "/api/v1/suppliers",
        json={"name": "Abarrotera Mayorista", "credit_days": 30},
        headers=headers,
    )
    supplier_id = supp_res.json()["id"]

    # 2. Crear 2 productos
    p1_res = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Arroz San Joaquín 1kg", "price_mxn": 24.00, "cost_mxn": 18.00, "stock": 10.0},
        headers=headers,
    )
    p1_id = p1_res.json()["id"]

    p2_res = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Frijol Negro 1kg", "price_mxn": 35.00, "cost_mxn": 28.00, "stock": 5.0},
        headers=headers,
    )
    p2_id = p2_res.json()["id"]

    # 3. Crear orden de compra
    po_payload = {
        "supplier_id": supplier_id,
        "items": [
            {"product_id": p1_id, "quantity_ordered": 50, "unit_cost_mxn": 17.50},
            {"product_id": p2_id, "quantity_ordered": 30, "unit_cost_mxn": 27.00},
        ],
        "notes": "Entrega prioritaria matutina",
    }
    po_res = await client.post("/api/v1/purchase-orders", json=po_payload, headers=headers)
    assert po_res.status_code == 201
    po_data = po_res.json()
    assert po_data["folio"].startswith("OC-")
    assert po_data["status"] == "CONFIRMED"
    # 50 * 17.50 = 875.00 ; 30 * 27.00 = 810.00 -> Total = 1685.00
    assert Decimal(str(po_data["subtotal_mxn"])) == Decimal("1685.00")
    assert Decimal(str(po_data["total_mxn"])) == Decimal("1685.00")
    assert len(po_data["items"]) == 2


@pytest.mark.asyncio
async def test_receive_purchase_order_full_and_kardex_stock_entry(client: AsyncClient):
    """
    Test 5: Recepción física total de orden de compra, incremento de existencias en almacén,
    asiento de movimiento Kardex (PURCHASE_ENTRY) y generación de Cuenta por Pagar (CxP) (RF-15, RF-16, RF-17).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes San Juan {suffix}",
            "slug": f"sanjuan-po-{suffix}",
            "full_name": "Dueño San Juan",
            "email": f"sanjuan_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Proveedor con 15 días de crédito
    supp_res = await client.post(
        "/api/v1/suppliers",
        json={"name": "Distribuidora de Harinas", "credit_days": 15},
        headers=headers,
    )
    supplier_id = supp_res.json()["id"]

    # 2. Producto con stock inicial de 10
    prod_res = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Harina de Trigo 1kg", "price_mxn": 22.00, "cost_mxn": 16.00, "initial_stock": 10.0},
        headers=headers,
    )
    product_id = prod_res.json()["id"]

    # 3. Emitir orden de compra por 100 piezas a $15.50
    po_res = await client.post(
        "/api/v1/purchase-orders",
        json={
            "supplier_id": supplier_id,
            "items": [{"product_id": product_id, "quantity_ordered": 100, "unit_cost_mxn": 15.50}],
        },
        headers=headers,
    )
    po_data = po_res.json()
    po_id = po_data["id"]
    po_item_id = po_data["items"][0]["id"]

    # 4. Recepcionar la orden completa
    receive_payload = {
        "items_received": [
            {
                "purchase_order_item_id": po_item_id,
                "quantity_received": 100,
                "unit_cost_mxn": 15.50,
                "lot_number": "LOTE-2026-X",
            }
        ],
        "invoice_reference": "FACT-99881",
        "notes": "Mercancía recibida en perfecto estado",
    }
    rec_res = await client.post(f"/api/v1/purchase-orders/{po_id}/receive", json=receive_payload, headers=headers)
    assert rec_res.status_code == 200
    rec_data = rec_res.json()
    assert rec_data["purchase_order"]["status"] == "RECEIVED"
    assert rec_data["stock_movements_count"] == 1
    assert rec_data["account_payable"] is not None
    assert rec_data["account_payable"]["folio"].startswith("CXP-")
    assert Decimal(str(rec_data["account_payable"]["total_mxn"])) == Decimal("1550.00")
    assert Decimal(str(rec_data["account_payable"]["pending_amount_mxn"])) == Decimal("1550.00")

    # 5. Verificar que el stock físico aumentó de 10 a 110
    prod_check = await client.get(f"/api/v1/inventory/products/{product_id}", headers=headers)
    assert prod_check.status_code == 200
    assert Decimal(str(prod_check.json()["total_stock"])) == Decimal("110.00")

    # 6. Verificar que el Kardex tiene el movimiento PURCHASE_ENTRY
    mov_res = await client.get("/api/v1/inventory/movements", headers=headers)
    assert mov_res.status_code == 200
    movements = mov_res.json()
    purchase_mov = next((m for m in movements if m["movement_type"] == "PURCHASE_ENTRY"), None)
    assert purchase_mov is not None
    assert Decimal(str(purchase_mov["quantity"])) == Decimal("100.00")
    assert Decimal(str(purchase_mov["new_stock"])) == Decimal("110.00")


@pytest.mark.asyncio
async def test_receive_purchase_order_partial(client: AsyncClient):
    """
    Test 6: Recepción parcial de orden de compra en dos entregas sucesivas.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Parcial {suffix}",
            "slug": f"parcial-po-{suffix}",
            "full_name": "Dueño Parcial",
            "email": f"parcial_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Proveedor y producto
    supp_res = await client.post("/api/v1/suppliers", json={"name": "Bebidas del Centro"}, headers=headers)
    supplier_id = supp_res.json()["id"]

    prod_res = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Agua Mineral 600ml", "price_mxn": 15.00, "cost_mxn": 9.00, "stock": 0.0},
        headers=headers,
    )
    product_id = prod_res.json()["id"]

    # Orden de 100 piezas
    po_res = await client.post(
        "/api/v1/purchase-orders",
        json={"supplier_id": supplier_id, "items": [{"product_id": product_id, "quantity_ordered": 100, "unit_cost_mxn": 9.00}]},
        headers=headers,
    )
    po_id = po_res.json()["id"]
    po_item_id = po_res.json()["items"][0]["id"]

    # Entrega 1: Recibir 40 piezas
    rec1 = await client.post(
        f"/api/v1/purchase-orders/{po_id}/receive",
        json={"items_received": [{"purchase_order_item_id": po_item_id, "quantity_received": 40}]},
        headers=headers,
    )
    assert rec1.status_code == 200
    assert rec1.json()["purchase_order"]["status"] == "PARTIALLY_RECEIVED"

    # Verificar stock = 40
    p_check1 = await client.get(f"/api/v1/inventory/products/{product_id}", headers=headers)
    assert Decimal(str(p_check1.json()["total_stock"])) == Decimal("40.00")

    # Entrega 2: Intentar recibir 70 piezas (supera las 60 pendientes) -> Debe fallar con HTTP 422
    rec_err = await client.post(
        f"/api/v1/purchase-orders/{po_id}/receive",
        json={"items_received": [{"purchase_order_item_id": po_item_id, "quantity_received": 70}]},
        headers=headers,
    )
    assert rec_err.status_code == 422

    # Entrega 2 real: Recibir las 60 restantes
    rec2 = await client.post(
        f"/api/v1/purchase-orders/{po_id}/receive",
        json={"items_received": [{"purchase_order_item_id": po_item_id, "quantity_received": 60}]},
        headers=headers,
    )
    assert rec2.status_code == 200
    assert rec2.json()["purchase_order"]["status"] == "RECEIVED"

    # Verificar stock final = 100
    p_check2 = await client.get(f"/api/v1/inventory/products/{product_id}", headers=headers)
    assert Decimal(str(p_check2.json()["total_stock"])) == Decimal("100.00")


@pytest.mark.asyncio
async def test_record_supplier_payment_partial_and_full(client: AsyncClient):
    """
    Test 7: Registro de abonos parciales y liquidación completa de Cuenta por Pagar a Proveedor (RF-16).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Pagos {suffix}",
            "slug": f"pagos-cxp-{suffix}",
            "full_name": "Dueño Pagos",
            "email": f"pagos_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Proveedor, producto y orden de $1,000.00
    supp_res = await client.post("/api/v1/suppliers", json={"name": "Carnes Frías del Norte", "credit_days": 20}, headers=headers)
    supplier_id = supp_res.json()["id"]

    prod_res = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Jamón de Pavo 500g", "price_mxn": 65.00, "cost_mxn": 50.00, "stock": 0.0},
        headers=headers,
    )
    product_id = prod_res.json()["id"]

    po_res = await client.post(
        "/api/v1/purchase-orders",
        json={"supplier_id": supplier_id, "items": [{"product_id": product_id, "quantity_ordered": 20, "unit_cost_mxn": 50.00}]},
        headers=headers,
    )
    po_id = po_res.json()["id"]
    po_item_id = po_res.json()["items"][0]["id"]

    # Recepcionar orden para generar la CxP de $1,000.00 MXN
    rec_res = await client.post(
        f"/api/v1/purchase-orders/{po_id}/receive",
        json={"items_received": [{"purchase_order_item_id": po_item_id, "quantity_received": 20}]},
        headers=headers,
    )
    cxp_id = rec_res.json()["account_payable"]["id"]

    # 1. Abono parcial de $400.00 MXN vía SPEI
    pay1_res = await client.post(
        f"/api/v1/accounts-payable/{cxp_id}/pay",
        json={
            "amount_paid_mxn": 400.00,
            "payment_method": "SPEI",
            "reference_code": "SPEI-12345678",
            "notes": "Primer abono quincenal",
        },
        headers=headers,
    )
    assert pay1_res.status_code == 200
    pay1_data = pay1_res.json()
    assert pay1_data["resulting_status"] == "PARTIALLY_PAID"
    assert Decimal(str(pay1_data["previous_pending_mxn"])) == Decimal("1000.00")
    assert Decimal(str(pay1_data["resulting_pending_mxn"])) == Decimal("600.00")

    # 2. Intentar abonar $700.00 (excede los $600.00 pendientes) -> Debe retornar HTTP 422
    pay_err = await client.post(
        f"/api/v1/accounts-payable/{cxp_id}/pay",
        json={"amount_paid_mxn": 700.00, "payment_method": "CASH_MXN"},
        headers=headers,
    )
    assert pay_err.status_code == 422

    # 3. Liquidar los $600.00 restantes en efectivo
    pay2_res = await client.post(
        f"/api/v1/accounts-payable/{cxp_id}/pay",
        json={"amount_paid_mxn": 600.00, "payment_method": "CASH_MXN", "notes": "Liquidación de factura"},
        headers=headers,
    )
    assert pay2_res.status_code == 200
    pay2_data = pay2_res.json()
    assert pay2_data["resulting_status"] == "PAID"
    assert Decimal(str(pay2_data["resulting_pending_mxn"])) == Decimal("0.00")

    # 4. Consultar historial de pagos de la cuenta (debe tener 2 asientos)
    history_res = await client.get(f"/api/v1/accounts-payable/{cxp_id}/payments", headers=headers)
    assert history_res.status_code == 200
    assert len(history_res.json()) == 2


@pytest.mark.asyncio
async def test_accounts_payable_summary_and_overdue_filter(client: AsyncClient):
    """
    Test 8: Cálculo consolidado del resumen de cuentas por pagar y filtro de cuentas vencidas.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Resumen Fin {suffix}",
            "slug": f"resumen-cxp-{suffix}",
            "full_name": "Dueño Resumen",
            "email": f"resumen_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Crear proveedor
    supp_res = await client.post("/api/v1/suppliers", json={"name": "Mayorista de Granos"}, headers=headers)
    supplier_id = supp_res.json()["id"]

    prod_res = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Lenteja 1kg", "price_mxn": 30.00, "cost_mxn": 20.00, "stock": 0.0},
        headers=headers,
    )
    product_id = prod_res.json()["id"]

    po_res = await client.post(
        "/api/v1/purchase-orders",
        json={"supplier_id": supplier_id, "items": [{"product_id": product_id, "quantity_ordered": 10, "unit_cost_mxn": 20.00}]},
        headers=headers,
    )
    po_id = po_res.json()["id"]
    po_item_id = po_res.json()["items"][0]["id"]

    # Recepcionar orden ($200.00 MXN)
    await client.post(
        f"/api/v1/purchase-orders/{po_id}/receive",
        json={"items_received": [{"purchase_order_item_id": po_item_id, "quantity_received": 10}]},
        headers=headers,
    )

    # Consultar resumen
    summary_res = await client.get("/api/v1/accounts-payable/summary", headers=headers)
    assert summary_res.status_code == 200
    s_data = summary_res.json()
    assert Decimal(str(s_data["total_pending_mxn"])) >= Decimal("200.00")
    assert s_data["pending_count"] >= 1


@pytest.mark.asyncio
async def test_purchases_and_suppliers_multi_tenant_rls_isolation(client: AsyncClient):
    """
    Test 9: Aislamiento estricto multi-tenant mediante Row Level Security (RLS)
    entre comercios independientes en proveedores, compras y cuentas por pagar.
    """
    # 1. Tenant A
    suffix_a = uuid.uuid4().hex[:6]
    reg_a = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Comercio A {suffix_a}",
            "slug": f"comercio-a-{suffix_a}",
            "full_name": "Dueño A",
            "email": f"tenant_a_{suffix_a}@tienda.mx",
            "password": "password123",
        },
    )
    token_a = reg_a.json()["access_token"]
    headers_a = {"Authorization": f"Bearer {token_a}"}

    # Tenant A crea proveedor
    supp_a = await client.post(
        "/api/v1/suppliers",
        json={"name": "Proveedor Secreto de A", "rfc": "SEC010101AAA"},
        headers=headers_a,
    )
    supp_a_id = supp_a.json()["id"]

    # 2. Tenant B
    suffix_b = uuid.uuid4().hex[:6]
    reg_b = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Comercio B {suffix_b}",
            "slug": f"comercio-b-{suffix_b}",
            "full_name": "Dueño B",
            "email": f"tenant_b_{suffix_b}@tienda.mx",
            "password": "password123",
        },
    )
    token_b = reg_b.json()["access_token"]
    headers_b = {"Authorization": f"Bearer {token_b}"}

    # Tenant B intenta consultar el proveedor de Tenant A -> Debe retornar 404
    cross_get = await client.get(f"/api/v1/suppliers/{supp_a_id}", headers=headers_b)
    assert cross_get.status_code == 404

    # Tenant B lista proveedores -> No debe ver el proveedor de Tenant A
    list_b = await client.get("/api/v1/suppliers", headers=headers_b)
    assert list_b.status_code == 200
    b_ids = [s["id"] for s in list_b.json()]
    assert supp_a_id not in b_ids


async def _tenant_with_order(client: AsyncClient, label: str):
    """Arma un inquilino con proveedor, producto y una orden de compra recién
    creada. Devuelve (headers, order_id, product_id)."""
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda {label} {suffix}",
            "slug": f"{label}-{suffix}",
            "full_name": f"Dueño {label}",
            "email": f"owner_{label}_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    headers = {"Authorization": f"Bearer {reg_resp.json()['access_token']}"}

    supp_res = await client.post(
        "/api/v1/suppliers",
        json={"name": "Abarrotera Mayorista", "credit_days": 15},
        headers=headers,
    )
    supplier_id = supp_res.json()["id"]

    prod_res = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Aceite 1L", "price_mxn": 40.00, "cost_mxn": 30.00, "stock": 0.0},
        headers=headers,
    )
    product_id = prod_res.json()["id"]

    po_res = await client.post(
        "/api/v1/purchase-orders",
        json={
            "supplier_id": supplier_id,
            "items": [{"product_id": product_id, "quantity_ordered": 10, "unit_cost_mxn": 30.00}],
            "notes": "Pedido inicial",
        },
        headers=headers,
    )
    return headers, po_res.json()["id"], product_id


@pytest.mark.asyncio
async def test_update_purchase_order_replaces_items_and_recalculates_total(client: AsyncClient):
    """
    Editar una orden que aún no recibe mercancía sustituye sus renglones y
    recalcula los totales (RF-15).
    """
    headers, order_id, product_id = await _tenant_with_order(client, "editable")

    put_res = await client.put(
        f"/api/v1/purchase-orders/{order_id}",
        json={
            "items": [{"product_id": product_id, "quantity_ordered": 4, "unit_cost_mxn": 32.50}],
            "expected_delivery_date": str(date.today() + timedelta(days=3)),
            "notes": "Se redujo el pedido por falta de espacio",
        },
        headers=headers,
    )
    assert put_res.status_code == 200
    data = put_res.json()

    # 4 × 32.50 = 130.00 — el renglón anterior (10 × 30.00) ya no existe.
    assert len(data["items"]) == 1
    assert Decimal(str(data["items"][0]["quantity_ordered"])) == Decimal("4")
    assert Decimal(str(data["total_mxn"])) == Decimal("130.00")
    assert data["notes"] == "Se redujo el pedido por falta de espacio"
    assert data["status"] == "CONFIRMED"


@pytest.mark.asyncio
async def test_cancel_purchase_order_keeps_history_with_reason(client: AsyncClient):
    """
    Cancelar no borra la orden: la deja en CANCELLED y anexa el motivo a las
    notas para que el historial siga contando lo que pasó.
    """
    headers, order_id, _ = await _tenant_with_order(client, "cancelable")

    cancel_res = await client.post(
        f"/api/v1/purchase-orders/{order_id}/cancel",
        json={"reason": "El proveedor ya no tiene existencias"},
        headers=headers,
    )
    assert cancel_res.status_code == 200
    data = cancel_res.json()
    assert data["status"] == "CANCELLED"
    assert "El proveedor ya no tiene existencias" in data["notes"]

    # Sigue existiendo: no se borró.
    get_res = await client.get(f"/api/v1/purchase-orders/{order_id}", headers=headers)
    assert get_res.status_code == 200
    assert get_res.json()["status"] == "CANCELLED"

    # Y no se puede cancelar dos veces.
    again = await client.post(
        f"/api/v1/purchase-orders/{order_id}/cancel", json={}, headers=headers
    )
    assert again.status_code == 422


@pytest.mark.asyncio
async def test_received_order_cannot_be_edited_or_cancelled(client: AsyncClient):
    """
    En cuanto entra mercancía hay stock asentado, movimientos de Kardex y una
    CxP creada: editar o cancelar dejaría al inventario describiendo algo que
    no pasó, así que el backend lo rechaza con 422.
    """
    headers, order_id, product_id = await _tenant_with_order(client, "recibida")

    detail = await client.get(f"/api/v1/purchase-orders/{order_id}", headers=headers)
    item_id = detail.json()["items"][0]["id"]

    recv = await client.post(
        f"/api/v1/purchase-orders/{order_id}/receive",
        json={"items_received": [{"purchase_order_item_id": item_id, "quantity_received": 10}]},
        headers=headers,
    )
    assert recv.status_code == 200

    put_res = await client.put(
        f"/api/v1/purchase-orders/{order_id}",
        json={"items": [{"product_id": product_id, "quantity_ordered": 1, "unit_cost_mxn": 10.0}]},
        headers=headers,
    )
    assert put_res.status_code == 422
    assert "ya recibió mercancía" in put_res.json()["detail"]

    cancel_res = await client.post(
        f"/api/v1/purchase-orders/{order_id}/cancel", json={}, headers=headers
    )
    assert cancel_res.status_code == 422


@pytest.mark.asyncio
async def test_partially_received_order_is_also_locked(client: AsyncClient):
    """
    Una entrega parcial ya movió stock y generó la CxP por el total: cuenta
    como orden empezada, no como orden intacta.
    """
    headers, order_id, _ = await _tenant_with_order(client, "parcial")

    detail = await client.get(f"/api/v1/purchase-orders/{order_id}", headers=headers)
    item_id = detail.json()["items"][0]["id"]

    recv = await client.post(
        f"/api/v1/purchase-orders/{order_id}/receive",
        json={"items_received": [{"purchase_order_item_id": item_id, "quantity_received": 3}]},
        headers=headers,
    )
    assert recv.status_code == 200
    assert recv.json()["purchase_order"]["status"] == "PARTIALLY_RECEIVED"

    cancel_res = await client.post(
        f"/api/v1/purchase-orders/{order_id}/cancel", json={}, headers=headers
    )
    assert cancel_res.status_code == 422
