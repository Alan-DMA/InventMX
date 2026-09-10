# Importación del módulo decimal para cálculos monetarios exactos
from decimal import Decimal
# Importación del módulo uuid para generar identificadores únicos
import uuid
# Importación del framework pytest para la ejecución de pruebas asíncronas
import pytest
# Importación del cliente HTTP asíncrono de httpx
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_open_shift_success(client: AsyncClient):
    """
    Test 1: Apertura exitosa de un nuevo turno de caja con fondo inicial en MXN (RF-16 / Const. Art. 3.3).
    Verifica que el turno se cree en estado OPEN con el fondo inicial asignado.
    """
    suffix = uuid.uuid4().hex[:6]
    # Registro de comercio
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Turnos {suffix}",
            "slug": f"turnos-open-{suffix}",
            "full_name": "Cajero Turno 1",
            "email": f"cajero_turnos_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Apertura de turno con fondo de $500.00 MXN
    open_payload = {
        "opening_balance_mxn": 500.00,
        "notes": "Apertura turno matutino caja 1",
    }
    open_res = await client.post("/api/v1/sales/shifts/open", json=open_payload, headers=headers)
    assert open_res.status_code == 201
    shift_data = open_res.json()
    assert shift_data["status"] == "OPEN"
    assert Decimal(str(shift_data["opening_balance_mxn"])) == Decimal("500.00")
    assert shift_data["counted_cash_mxn"] is None
    assert shift_data["expected_cash_mxn"] is None
    assert shift_data["closed_at"] is None


@pytest.mark.asyncio
async def test_open_shift_duplicate_conflict_error(client: AsyncClient):
    """
    Test 2: Validación de conflicto al intentar abrir dos turnos activos simultáneamente para el mismo cajero.
    Debe retornar HTTP 409 CONFLICT.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Conflicto {suffix}",
            "slug": f"conflict-shift-{suffix}",
            "full_name": "Cajero Conflicto",
            "email": f"cajero_conflict_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Primera apertura -> 201 OK
    res1 = await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 300.00},
        headers=headers,
    )
    assert res1.status_code == 201

    # Segunda apertura sin cerrar la primera -> 409 Conflict
    res2 = await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 200.00},
        headers=headers,
    )
    assert res2.status_code == 409
    assert "ya cuenta con un turno de caja activo" in res2.json()["detail"]


@pytest.mark.asyncio
async def test_get_current_active_shift(client: AsyncClient):
    """
    Test 3: Consulta del turno actualmente abierto del cajero en sesión (/shifts/current).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Current {suffix}",
            "slug": f"current-shift-{suffix}",
            "full_name": "Cajero Current",
            "email": f"cajero_current_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Antes de abrir turno, debe retornar null
    res_before = await client.get("/api/v1/sales/shifts/current", headers=headers)
    assert res_before.status_code == 200
    assert res_before.json() is None

    # Abrir turno
    open_res = await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 400.00},
        headers=headers,
    )
    assert open_res.status_code == 201
    shift_id = open_res.json()["id"]

    # Consultar turno activo
    res_after = await client.get("/api/v1/sales/shifts/current", headers=headers)
    assert res_after.status_code == 200
    current_data = res_after.json()
    assert current_data is not None
    assert current_data["id"] == shift_id
    assert current_data["status"] == "OPEN"


@pytest.mark.asyncio
async def test_record_cash_movements_in_and_out(client: AsyncClient):
    """
    Test 4: Registro de movimientos manuales de caja chica (CASH_IN y CASH_OUT) (RF-16).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Movimientos {suffix}",
            "slug": f"movs-shift-{suffix}",
            "full_name": "Cajero Movimientos",
            "email": f"cajero_movs_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Abrir turno
    open_res = await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 1000.00},
        headers=headers,
    )
    assert open_res.status_code == 201
    shift_id = open_res.json()["id"]

    # 1. Registrar CASH_IN (Aportación de morralla/cambio)
    in_res = await client.post(
        f"/api/v1/sales/shifts/{shift_id}/movements",
        json={
            "movement_type": "CASH_IN",
            "amount_mxn": 250.00,
            "reason": "Aporte de monedas de $5 y $10",
        },
        headers=headers,
    )
    assert in_res.status_code == 201
    in_data = in_res.json()
    assert in_data["movement_type"] == "CASH_IN"
    assert Decimal(str(in_data["amount_mxn"])) == Decimal("250.00")

    # 2. Registrar CASH_OUT (Pago de garrafón)
    out_res = await client.post(
        f"/api/v1/sales/shifts/{shift_id}/movements",
        json={
            "movement_type": "CASH_OUT",
            "amount_mxn": 85.00,
            "reason": "Pago de 2 garrafones de agua Ciel",
        },
        headers=headers,
    )
    assert out_res.status_code == 201
    out_data = out_res.json()
    assert out_data["movement_type"] == "CASH_OUT"
    assert Decimal(str(out_data["amount_mxn"])) == Decimal("85.00")

    # Consultar detalle del turno y verificar que contenga los 2 movimientos
    detail_res = await client.get(f"/api/v1/sales/shifts/{shift_id}", headers=headers)
    assert detail_res.status_code == 200
    shift_detail = detail_res.json()
    assert len(shift_detail["movements"]) == 2


@pytest.mark.asyncio
async def test_record_movement_on_closed_shift_fails(client: AsyncClient):
    """
    Test 5: Intentar registrar un movimiento de caja chica en un turno CERRADO debe fallar con HTTP 400.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Closed Move {suffix}",
            "slug": f"closed-move-{suffix}",
            "full_name": "Cajero Closed",
            "email": f"cajero_closed_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Abrir turno
    open_res = await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 500.00},
        headers=headers,
    )
    shift_id = open_res.json()["id"]

    # Cerrar turno
    close_res = await client.post(
        f"/api/v1/sales/shifts/{shift_id}/close",
        json={"counted_cash_mxn": 500.00, "notes": "Cierre normal"},
        headers=headers,
    )
    assert close_res.status_code == 200

    # Intentar movimiento en turno cerrado -> 400 Bad Request
    fail_res = await client.post(
        f"/api/v1/sales/shifts/{shift_id}/movements",
        json={
            "movement_type": "CASH_IN",
            "amount_mxn": 100.00,
            "reason": "Intento de depósito tardío",
        },
        headers=headers,
    )
    assert fail_res.status_code == 400
    assert "se encuentra cerrado" in fail_res.json()["detail"]


@pytest.mark.asyncio
async def test_blind_cash_audit_exact_match(client: AsyncClient):
    """
    Test 6: Arqueo a Ciegas con cuadre exacto ($0.00 de diferencia / EXACT) (RF-17).
    Fondo: $500.00 + Ventas Efectivo: $100.00 + Depósito: $50.00 - Retiro: $20.00 = Esperado: $630.00.
    Conteo Físico: $630.00 -> Diferencia: $0.00.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Exacto {suffix}",
            "slug": f"audit-exact-{suffix}",
            "full_name": "Cajero Exacto",
            "email": f"cajero_exact_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear producto de prueba ($50.00)
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Aceite 1L",
            "barcode": f"7509{suffix[:8]}",
            "price_mxn": 50.00,
            "cost_mxn": 35.00,
            "initial_stock": 100.0,
        },
        headers=headers,
    )
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # 2. Abrir turno con $500.00
    open_res = await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 500.00, "warehouse_id": warehouse_id},
        headers=headers,
    )
    assert open_res.status_code == 201
    shift_id = open_res.json()["id"]

    # 3. Realizar venta de 2 piezas ($100.00) en efectivo
    await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "items": [{"product_id": product_id, "quantity": 2.0, "unit_price_mxn": 50.00}],
            "payments": [{"payment_method": "CASH_MXN", "amount_paid_mxn": 100.00}],
        },
        headers=headers,
    )

    # 4. Movimientos manuales: +$50.00 y -$20.00
    await client.post(
        f"/api/v1/sales/shifts/{shift_id}/movements",
        json={"movement_type": "CASH_IN", "amount_mxn": 50.00, "reason": "Cambio"},
        headers=headers,
    )
    await client.post(
        f"/api/v1/sales/shifts/{shift_id}/movements",
        json={"movement_type": "CASH_OUT", "amount_mxn": 20.00, "reason": "Limpieza"},
        headers=headers,
    )

    # 5. Cerrar turno con conteo exacto de $630.00
    close_res = await client.post(
        f"/api/v1/sales/shifts/{shift_id}/close",
        json={"counted_cash_mxn": 630.00, "notes": "Cierre exacto"},
        headers=headers,
    )
    assert close_res.status_code == 200
    closed_data = close_res.json()
    assert closed_data["status"] == "CLOSED"
    assert Decimal(str(closed_data["expected_cash_mxn"])) == Decimal("630.00")
    assert Decimal(str(closed_data["counted_cash_mxn"])) == Decimal("630.00")
    assert Decimal(str(closed_data["difference_mxn"])) == Decimal("0.00")

    # 6. Consultar resumen financiero
    summary_res = await client.get(f"/api/v1/sales/shifts/{shift_id}/summary", headers=headers)
    assert summary_res.status_code == 200
    sum_data = summary_res.json()
    assert sum_data["difference_status"] == "EXACT"
    assert Decimal(str(sum_data["total_cash_sales_mxn"])) == Decimal("100.00")


@pytest.mark.asyncio
async def test_blind_cash_audit_surplus(client: AsyncClient):
    """
    Test 7: Arqueo a Ciegas con Sobrante (SURPLUS / Dinero extra no registrado) (RF-17).
    Esperado: $500.00. Conteo Físico: $535.50 -> Diferencia: +$35.50 (SURPLUS).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Sobrante {suffix}",
            "slug": f"audit-surplus-{suffix}",
            "full_name": "Cajero Sobrante",
            "email": f"cajero_surplus_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Abrir turno con $500.00
    open_res = await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 500.00},
        headers=headers,
    )
    shift_id = open_res.json()["id"]

    # Cerrar turno con $535.50
    close_res = await client.post(
        f"/api/v1/sales/shifts/{shift_id}/close",
        json={"counted_cash_mxn": 535.50, "notes": "Sobrante de propinas no registradas"},
        headers=headers,
    )
    assert close_res.status_code == 200
    closed_data = close_res.json()
    assert Decimal(str(closed_data["difference_mxn"])) == Decimal("35.50")

    # Resumen
    summary_res = await client.get(f"/api/v1/sales/shifts/{shift_id}/summary", headers=headers)
    assert summary_res.status_code == 200
    assert summary_res.json()["difference_status"] == "SURPLUS"


@pytest.mark.asyncio
async def test_blind_cash_audit_shortage(client: AsyncClient):
    """
    Test 8: Arqueo a Ciegas con Faltante (SHORTAGE / Pérdida o desvío) (RF-17).
    Esperado: $500.00. Conteo Físico: $460.00 -> Diferencia: -$40.00 (SHORTAGE).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Faltante {suffix}",
            "slug": f"audit-shortage-{suffix}",
            "full_name": "Cajero Faltante",
            "email": f"cajero_shortage_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Abrir turno con $500.00
    open_res = await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 500.00},
        headers=headers,
    )
    shift_id = open_res.json()["id"]

    # Cerrar turno con $460.00
    close_res = await client.post(
        f"/api/v1/sales/shifts/{shift_id}/close",
        json={"counted_cash_mxn": 460.00, "notes": "Faltante en caja por cambio mal dado"},
        headers=headers,
    )
    assert close_res.status_code == 200
    closed_data = close_res.json()
    assert Decimal(str(closed_data["difference_mxn"])) == Decimal("-40.00")

    # Resumen
    summary_res = await client.get(f"/api/v1/sales/shifts/{shift_id}/summary", headers=headers)
    assert summary_res.status_code == 200
    assert summary_res.json()["difference_status"] == "SHORTAGE"


@pytest.mark.asyncio
async def test_shift_summary_financial_breakdown_mixed_payments(client: AsyncClient):
    """
    Test 9: Cuadre financiero integral con ventas mixtas (Efectivo, Tarjeta TPV y SPEI).
    Verifica que las tarjetas y transferencias electrónicas no incrementen erróneamente el saldo esperado en efectivo de caja.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Finanzas {suffix}",
            "slug": f"audit-finances-{suffix}",
            "full_name": "Cajero Finanzas",
            "email": f"cajero_finances_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Crear producto ($100.00)
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Bolsa de Café 500g",
            "barcode": f"7501{suffix[:8]}",
            "price_mxn": 100.00,
            "cost_mxn": 60.00,
            "initial_stock": 100.0,
        },
        headers=headers,
    )
    prod_data = prod_resp.json()
    product_id = prod_data["id"]
    warehouse_id = prod_data["stocks"][0]["warehouse_id"]

    # 1. Abrir turno con $1,000.00
    open_res = await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 1000.00, "warehouse_id": warehouse_id},
        headers=headers,
    )
    shift_id = open_res.json()["id"]

    # 2. Venta 1: 1 pieza ($100.00) en Efectivo (CASH_MXN)
    await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "items": [{"product_id": product_id, "quantity": 1.0, "unit_price_mxn": 100.00}],
            "payments": [{"payment_method": "CASH_MXN", "amount_paid_mxn": 100.00}],
        },
        headers=headers,
    )

    # 3. Venta 2: 3 piezas ($300.00) pagadas con Tarjeta TPV (CARD_TPV)
    await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "items": [{"product_id": product_id, "quantity": 3.0, "unit_price_mxn": 100.00}],
            "payments": [{"payment_method": "CARD_TPV", "amount_paid_mxn": 300.00}],
        },
        headers=headers,
    )

    # 4. Venta 3: 2 piezas ($200.00) divididas ($50.00 Efectivo + $150.00 SPEI)
    await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "items": [{"product_id": product_id, "quantity": 2.0, "unit_price_mxn": 100.00}],
            "payments": [
                {"payment_method": "CASH_MXN", "amount_paid_mxn": 50.00},
                {"payment_method": "SPEI", "amount_paid_mxn": 150.00},
            ],
        },
        headers=headers,
    )

    # 5. Movimiento de caja: Retiro de $100.00 (CASH_OUT)
    await client.post(
        f"/api/v1/sales/shifts/{shift_id}/movements",
        json={"movement_type": "CASH_OUT", "amount_mxn": 100.00, "reason": "Corte parcial de caja"},
        headers=headers,
    )

    # 6. Consultar resumen contable del turno
    summary_res = await client.get(f"/api/v1/sales/shifts/{shift_id}/summary", headers=headers)
    assert summary_res.status_code == 200
    sum_data = summary_res.json()

    # Total Ventas Brutas: $100 + $300 + $200 = $600.00
    assert Decimal(str(sum_data["total_sales_mxn"])) == Decimal("600.00")
    # Ventas en Efectivo: $100 + $50 = $150.00
    assert Decimal(str(sum_data["total_cash_sales_mxn"])) == Decimal("150.00")
    # Total Salidas: $100.00
    assert Decimal(str(sum_data["total_cash_out_mxn"])) == Decimal("100.00")
    # Saldo Teórico Esperado en Efectivo: 1000 + 150 - 100 = $1,050.00
    assert Decimal(str(sum_data["expected_cash_mxn"])) == Decimal("1050.00")

    # Verificar que el desglose tenga registros de CASH_MXN, CARD_TPV y SPEI
    methods = {item["payment_method"]: Decimal(str(item["total_mxn"])) for item in sum_data["payment_methods_summary"]}
    assert methods["CASH_MXN"] == Decimal("150.00")
    assert methods["CARD_TPV"] == Decimal("300.00")
    assert methods["SPEI"] == Decimal("150.00")
