"""
Integración del módulo de Caja (Oct 2026, antes del QA general). Fallas halladas
contra el servidor real:

B1 el turno activo traía un esperado sin las ventas · B2 el Corte Z inventaba
datos · B3 la lista de turnos sin nombre ni resultado · B4 el servidor aceptaba
retiros mayores al efectivo en caja.
"""
import uuid
from decimal import Decimal

import pytest
from httpx import AsyncClient

API = "/api/v1"


async def _store(client: AsyncClient):
    s = uuid.uuid4().hex[:6]
    reg = await client.post(f"{API}/auth/register", json={
        "store_name": f"Caja {s}", "slug": f"caja-{s}", "full_name": "Rosa Martínez",
        "email": f"caja_{s}@tienda.mx", "password": "password123",
    })
    assert reg.status_code == 201, reg.text
    h = {"Authorization": f"Bearer {reg.json()['access_token']}"}
    wid = (await client.get(f"{API}/inventory/warehouses", headers=h)).json()[0]["id"]
    pid = (await client.post(f"{API}/inventory/products", json={"name": "Coca-Cola 600ml", "price_mxn": "18.00"}, headers=h)).json()["id"]
    await client.post(f"{API}/inventory/adjust-stock", json={
        "product_id": pid, "warehouse_id": wid, "quantity": 50, "reason": "Inventario inicial"}, headers=h)
    return h, wid, pid


async def _sell(client, h, wid, pid, qty, method, paid, ref=None, payments=None, kept=False):
    payment = {"payment_method": method, "amount_paid_mxn": paid}
    if ref:
        payment["reference_code"] = ref
    body = {
        "warehouse_id": wid,
        "items": [{"product_id": pid, "quantity": qty, "unit_price_mxn": 18.0}],
        "payments": payments or [payment],
    }
    if kept:
        body["customer_kept_no_change"] = True
    r = await client.post(f"{API}/sales/checkout", json=body, headers=h)
    assert r.status_code == 201, r.text
    return r.json()


def _d(value) -> Decimal:
    return Decimal(str(value))


@pytest.mark.asyncio
async def test_active_session_is_the_source_of_truth(client: AsyncClient):
    """B1: el esperado del turno activo cuenta las ventas en efectivo netas de cambio."""
    h, wid, pid = await _store(client)
    assert (await client.get(f"{API}/cash/active-session", headers=h)).json() is None

    opened = await client.post(f"{API}/cash/open-session", json={"opening_amount_mxn": 600}, headers=h)
    assert opened.status_code == 201
    sid = opened.json()["id"]
    assert opened.json()["warehouse_id"] == wid

    await _sell(client, h, wid, pid, 2, "CASH_MXN", 50.0)        # $36 con $50: entran $36
    await _sell(client, h, wid, pid, 1, "SPEI", 18.0, "ABC123")  # digital: no entra al cajón
    await client.post(f"{API}/cash/sessions/{sid}/movements",
                      json={"type": "WITHDRAWAL", "amount_mxn": 100, "description": "Hielo"}, headers=h)
    await client.post(f"{API}/cash/sessions/{sid}/movements",
                      json={"type": "DEPOSIT", "amount_mxn": 50, "description": "Cambio extra"}, headers=h)

    active = (await client.get(f"{API}/cash/active-session", headers=h)).json()
    assert _d(active["expected_cash_mxn"]) == Decimal("586.00")  # 600 + 36 + 50 − 100
    summary = active["summary"]
    assert _d(summary["cash_sales_mxn"]) == Decimal("36.00")
    assert _d(summary["deposits_mxn"]) == Decimal("50.00") and _d(summary["withdrawals_mxn"]) == Decimal("100.00")
    assert {k: _d(v) for k, v in summary["digital_totals_mxn"].items()} == {"SPEI": Decimal("18.00")}
    assert summary["sales_count"] == 2 and _d(summary["sales_total_mxn"]) == Decimal("54.00")
    assert summary["movements_count"] == 2

    # Abrir otra vez con el turno abierto: 422 (la app lo retoma en vez de abrir)
    again = await client.post(f"{API}/cash/open-session", json={"opening_amount_mxn": 100}, headers=h)
    assert again.status_code == 422


@pytest.mark.asyncio
async def test_withdrawal_larger_than_cash_is_rejected_by_the_server(client: AsyncClient):
    """B4: el servidor no deja sacar más efectivo del que hay."""
    h, wid, pid = await _store(client)
    sid = (await client.post(f"{API}/cash/open-session", json={"opening_amount_mxn": 500}, headers=h)).json()["id"]
    await _sell(client, h, wid, pid, 5, "CASH_MXN", 100.0)  # +90
    too_much = await client.post(f"{API}/cash/sessions/{sid}/movements",
                                 json={"type": "WITHDRAWAL", "amount_mxn": 590.01, "description": "Retiro"}, headers=h)
    assert too_much.status_code == 422
    detail = too_much.json()["detail"]
    assert detail["code"] == "INSUFFICIENT_CASH_FOR_WITHDRAWAL" and detail["available_mxn"] == "590.00"
    exact = await client.post(f"{API}/cash/sessions/{sid}/movements",
                              json={"type": "WITHDRAWAL", "amount_mxn": 590, "description": "Retiro total"}, headers=h)
    assert exact.status_code == 201
    # Las entradas no tienen tope
    assert (await client.post(f"{API}/cash/sessions/{sid}/movements",
                              json={"type": "DEPOSIT", "amount_mxn": 9000, "description": "Fondo"}, headers=h)).status_code == 201


@pytest.mark.asyncio
async def test_close_report_and_list_carry_real_data(client: AsyncClient):
    """Cierre anidado con el resultado real · B2 Corte Z real · B3 lista con nombre y resultado."""
    h, wid, pid = await _store(client)
    sid = (await client.post(f"{API}/cash/open-session", json={"opening_amount_mxn": 600}, headers=h)).json()["id"]
    await _sell(client, h, wid, pid, 2, "CASH_MXN", 50.0)
    await _sell(client, h, wid, pid, 1, "CARD_TPV", 18.0)
    await client.post(f"{API}/cash/sessions/{sid}/movements",
                      json={"type": "WITHDRAWAL", "amount_mxn": 100, "description": "Hielo"}, headers=h)

    # Esperado 536; se cuentan 530 → faltan 6
    closed = await client.post(f"{API}/cash/close-session", json={
        "physical_denominations": {"bills_500": 1, "bills_20": 1, "coins_10": 1},
    }, headers=h)
    assert closed.status_code == 200, closed.text
    body = closed.json()
    assert _d(body["balance_summary"]["expected_cash_mxn"]) == Decimal("536.00")
    assert _d(body["balance_summary"]["difference_mxn"]) == Decimal("-6.00")
    assert body["balance_summary"]["balance_result"] == "SHORT"
    assert body["session"]["status"] == "CLOSED" and body["session"]["summary"]["sales_count"] == 2

    report = (await client.get(f"{API}/cash/sessions/{sid}/report", headers=h)).json()
    assert report["cashier_name"] == "Rosa Martínez"
    sales = report["sales_summary"]
    assert sales["total_sales_count"] == 2
    assert _d(sales["cash_sales_mxn"]) == Decimal("36.00") and _d(sales["digital_sales_mxn"]) == Decimal("18.00")
    assert _d(sales["average_ticket_mxn"]) == Decimal("27.00")
    assert _d(report["cash_balance"]["expected_closing_mxn"]) == Decimal("536.00")
    assert report["cash_balance"]["balance_result"] == "SHORT"
    assert report["movements_summary"]["movements_count"] == 1
    assert _d(report["movements_summary"]["total_withdrawals_mxn"]) == Decimal("100.00")

    listed = (await client.get(f"{API}/cash/sessions", headers=h)).json()["items"]
    assert listed[0]["cashier_name"] == "Rosa Martínez" and listed[0]["balance_result"] == "SHORT"
    assert (await client.get(f"{API}/cash/active-session", headers=h)).json() is None


@pytest.mark.asyncio
async def test_change_is_already_out_of_the_drawer(client: AsyncClient):
    """V1 + V5: el cambio se descuenta solo, también en pago mixto; el resumen dice recibido y cambio."""
    h, wid, pid = await _store(client)
    await client.post(f"{API}/cash/open-session", json={"opening_amount_mxn": 500}, headers=h)
    await _sell(client, h, wid, pid, 2, "CASH_MXN", 50.0)                       # $36 con $50 → cambio $14
    # Mixto: $54 = $40 tarjeta + $20 efectivo → cambio $6 sólo de lo entregado en efectivo
    await _sell(client, h, wid, pid, 3, None, None, payments=[
        {"payment_method": "CARD_TPV", "amount_paid_mxn": 40.0},
        {"payment_method": "CASH_MXN", "amount_paid_mxn": 20.0},
    ])
    summary = (await client.get(f"{API}/cash/active-session", headers=h)).json()["summary"]
    assert _d(summary["cash_received_mxn"]) == Decimal("70.00")
    assert _d(summary["change_given_mxn"]) == Decimal("20.00")
    assert _d(summary["cash_sales_mxn"]) == Decimal("50.00")                  # 36 + 14
    assert _d(summary["digital_totals_mxn"]["CARD_TPV"]) == Decimal("40.00")


@pytest.mark.asyncio
async def test_customer_kept_the_change(client: AsyncClient):
    """V7: el cliente no quiso el cambio → no se entrega, queda en la caja y la venta lo anota."""
    h, wid, pid = await _store(client)
    await client.post(f"{API}/cash/open-session", json={"opening_amount_mxn": 100}, headers=h)
    sale = await _sell(client, h, wid, pid, 2, "CASH_MXN", 40.0, kept=True)    # $36 con $40
    assert _d(sale["change_returned_mxn"]) == Decimal("0.00")
    assert "no quiso el cambio: $4.00" in sale["notes"]
    active = (await client.get(f"{API}/cash/active-session", headers=h)).json()
    assert _d(active["expected_cash_mxn"]) == Decimal("140.00")


@pytest.mark.asyncio
async def test_cash_refund_leaves_the_drawer_as_a_withdrawal(client: AsyncClient):
    """V6: un reembolso parcial ya no saca la venta entera del cuadre; sale lo devuelto."""
    h, wid, pid = await _store(client)
    sid = (await client.post(f"{API}/cash/open-session", json={"opening_amount_mxn": 100}, headers=h)).json()["id"]
    sale = await _sell(client, h, wid, pid, 2, "CASH_MXN", 50.0)               # +36
    item_id = sale["items"][0]["id"]
    refund = await client.post(f"{API}/sales/{sale['id']}/refund", json={
        "reason": "Una botella venía rota", "refund_to_stock": False,
        "items": [{"sale_item_id": item_id, "quantity": 1}],
    }, headers=h)
    assert refund.status_code == 200, refund.text
    active = (await client.get(f"{API}/cash/active-session", headers=h)).json()
    assert _d(active["expected_cash_mxn"]) == Decimal("118.00")               # 100 + 36 − 18
    movements = (await client.get(f"{API}/cash/sessions/{sid}/movements", headers=h)).json()
    assert [(m["type"], _d(m["amount_mxn"])) for m in movements] == [("WITHDRAWAL", Decimal("18.00"))]
    assert movements[0]["description"].startswith("Reembolso de VTA-")
