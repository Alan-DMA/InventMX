"""
Serie diaria de ventas (`GET /analytics/sales-trends`) y comisiones automáticas por
empleado (RF-10: tasa configurable en `PUT /users/{id}`, asiento al cobrar en checkout,
tablero en `GET /analytics/commissions` con `period_month` y desglose diario).
"""
import uuid
from datetime import datetime
from decimal import Decimal

import pytest
from httpx import AsyncClient


async def _register_store(client: AsyncClient, suffix: str) -> dict:
    """Registra un comercio y devuelve headers autenticados + datos del dueño."""
    reg = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Trends {suffix}",
            "slug": f"abarrotes-trends-{suffix}",
            "full_name": "Dueño Reportes",
            "email": f"reportes_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    assert reg.status_code == 201, reg.text
    headers = {"Authorization": f"Bearer {reg.json()['access_token']}"}
    me = await client.get("/api/v1/auth/me", headers=headers)
    assert me.status_code == 200
    return {"headers": headers, "user": me.json()}


async def _create_product(client: AsyncClient, headers: dict, suffix: str, price: float, cost: float) -> dict:
    res = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": f"Producto {suffix}",
            "sku": f"SKU-{suffix}",
            "price_mxn": price,
            "cost_mxn": cost,
            "initial_stock": 50,
        },
        headers=headers,
    )
    assert res.status_code == 201, res.text
    return res.json()


async def _checkout(client: AsyncClient, headers: dict, warehouse_id: str, product_id: str, qty: int, price: float) -> dict:
    res = await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "items": [{"product_id": product_id, "quantity": qty, "unit_price_mxn": price}],
            "payments": [{"payment_method": "CASH_MXN", "amount_paid_mxn": qty * price}],
            "discount_mxn": 0.00,
        },
        headers=headers,
    )
    assert res.status_code == 201, res.text
    return res.json()


@pytest.mark.asyncio
async def test_sales_trends_daily_series_is_net_of_refunds(client: AsyncClient):
    """
    Dos ventas hoy ($200 + $50) y una devolución parcial de $100: la serie de HOY reporta
    $150 neto, 2 tickets y utilidad = neto − costo de las piezas no devueltas, y la suma de
    la serie cuadra con `net_sales_mxn` de /financial-summary (misma base).
    """
    suffix = uuid.uuid4().hex[:6]
    store = await _register_store(client, suffix)
    headers = store["headers"]

    p1 = await _create_product(client, headers, f"A{suffix}", price=100.00, cost=60.00)
    p2 = await _create_product(client, headers, f"B{suffix}", price=50.00, cost=30.00)
    warehouse_id = p1["stocks"][0]["warehouse_id"]

    shift = await client.post("/api/v1/sales/shifts/open", json={"opening_balance_mxn": 500.00}, headers=headers)
    assert shift.status_code == 201

    sale1 = await _checkout(client, headers, warehouse_id, p1["id"], qty=2, price=100.00)
    await _checkout(client, headers, warehouse_id, p2["id"], qty=1, price=50.00)

    # Devolver 1 de las 2 piezas de la venta 1 ($100)
    item_id = sale1["items"][0]["id"]
    refund = await client.post(
        f"/api/v1/sales/{sale1['id']}/refund",
        json={
            "reason": "Pieza dañada",
            "refund_to_stock": True,
            "items": [{"sale_item_id": item_id, "quantity": 1}],
        },
        headers=headers,
    )
    assert refund.status_code == 200, refund.text

    trends = await client.get("/api/v1/analytics/sales-trends?preset=TODAY", headers=headers)
    assert trends.status_code == 200, trends.text
    data = trends.json()
    assert data["granularity"] == "daily"
    assert len(data["trends"]) == 1
    today = data["trends"][0]
    assert today["period"] == datetime.now().date().isoformat()
    assert Decimal(str(today["revenue_mxn"])) == Decimal("150.00")
    assert today["orders_count"] == 2
    # Utilidad: (100 − 60) por la pieza que se quedó + (50 − 30) = 60
    assert Decimal(str(today["gross_profit_mxn"])) == Decimal("60.00")

    # THIS_WEEK: un punto por día natural desde el lunes hasta hoy, los demás en cero
    week = await client.get("/api/v1/analytics/sales-trends?preset=THIS_WEEK", headers=headers)
    assert week.status_code == 200
    points = week.json()["trends"]
    assert len(points) == datetime.now().weekday() + 1
    assert Decimal(str(points[-1]["revenue_mxn"])) == Decimal("150.00")
    assert all(Decimal(str(p["revenue_mxn"])) == Decimal("0") for p in points[:-1])

    # La serie cuadra con el resumen financiero (mismo criterio neto)
    fin = await client.get("/api/v1/analytics/financial-summary?preset=TODAY", headers=headers)
    assert fin.status_code == 200
    assert Decimal(str(fin.json()["net_sales_mxn"])) == Decimal("150.00")
    assert Decimal(str(fin.json()["refunds_mxn"])) == Decimal("100.00")
    assert Decimal(str(fin.json()["gross_profit_mxn"])) == Decimal("60.00")
    assert fin.json()["total_transactions"] == 2

    # Lo más vendido también en neto: 1 pieza de A (no 2)
    inv = await client.get("/api/v1/analytics/inventory-health?preset=TODAY", headers=headers)
    assert inv.status_code == 200
    top = {t["product_id"]: t for t in inv.json()["top_selling_products"]}
    assert Decimal(str(top[p1["id"]]["units_sold"])) == Decimal("1.00")
    assert Decimal(str(top[p1["id"]]["revenue_mxn"])) == Decimal("100.00")
    assert Decimal(str(top[p1["id"]]["profit_mxn"])) == Decimal("40.00")


@pytest.mark.asyncio
async def test_sales_trends_custom_range_and_empty_days(client: AsyncClient):
    """Un rango CUSTOM sin ventas devuelve todos sus días en cero (nunca una lista vacía)."""
    suffix = uuid.uuid4().hex[:6]
    store = await _register_store(client, suffix)
    res = await client.get(
        "/api/v1/analytics/sales-trends",
        params={"preset": "CUSTOM", "start_date": "2026-03-02T00:00:00", "end_date": "2026-03-04T23:59:59"},
        headers=store["headers"],
    )
    assert res.status_code == 200, res.text
    points = res.json()["trends"]
    assert [p["period"] for p in points] == ["2026-03-02", "2026-03-03", "2026-03-04"]
    assert all(p["orders_count"] == 0 for p in points)


@pytest.mark.asyncio
async def test_commission_settings_and_automatic_commission_on_checkout(client: AsyncClient):
    """
    RF-10 completo: el dueño configura 5 % sobre venta en su propio usuario, cobra dos
    ventas y el tablero muestra $12.50 (5 % de $250), tasa vigente y desglose de hoy.
    Cancelar una venta saca su comisión del acumulado sin tocar el asiento.
    """
    suffix = uuid.uuid4().hex[:6]
    store = await _register_store(client, suffix)
    headers = store["headers"]
    user_id = store["user"]["id"]

    # Sin configurar: nada comisiona
    assert Decimal(str(store["user"]["commission_rate"])) == Decimal("0")

    # Configurar 5 % sobre venta
    upd = await client.put(
        f"/api/v1/users/{user_id}",
        json={"commission_type": "PERCENTAGE_SALE", "commission_rate": 5},
        headers=headers,
    )
    assert upd.status_code == 200, upd.text
    assert upd.json()["commission_type"] == "PERCENTAGE_SALE"
    assert Decimal(str(upd.json()["commission_rate"])) == Decimal("5")

    # Un porcentaje > 100 se rechaza
    bad = await client.put(f"/api/v1/users/{user_id}", json={"commission_rate": 150}, headers=headers)
    assert bad.status_code == 400, bad.text

    p1 = await _create_product(client, headers, f"C{suffix}", price=100.00, cost=60.00)
    warehouse_id = p1["stocks"][0]["warehouse_id"]
    shift = await client.post("/api/v1/sales/shifts/open", json={"opening_balance_mxn": 100.00}, headers=headers)
    assert shift.status_code == 201

    await _checkout(client, headers, warehouse_id, p1["id"], qty=2, price=100.00)  # $200 -> $10
    sale2 = await _checkout(client, headers, warehouse_id, p1["id"], qty=1, price=50.00)  # $50 -> $2.50

    month = datetime.now().strftime("%Y-%m")
    rep = await client.get(f"/api/v1/analytics/commissions?period_month={month}", headers=headers)
    assert rep.status_code == 200, rep.text
    data = rep.json()
    assert data["period"] == month
    assert data["current_user"]["cashier_id"] == user_id
    assert data["current_user"]["commission_type"] == "PERCENTAGE_SALE"
    assert Decimal(str(data["current_user"]["commission_rate"])) == Decimal("5")

    # Privacidad: el tablero es sólo del usuario en sesión — nada de otros empleados
    assert "ranking" not in data and "cashiers" not in data and "summaries_by_user" not in data
    assert Decimal(str(data["summary"]["earned_commission_mxn"])) == Decimal("12.50")
    assert Decimal(str(data["summary"]["total_sales_mxn"])) == Decimal("250.00")
    assert data["summary"]["sales_count"] == 2

    assert len(data["daily_breakdown"]) == 1
    today = data["daily_breakdown"][0]
    assert today["date"] == datetime.now().date().isoformat()
    assert today["sales_count"] == 2
    assert Decimal(str(today["commission_mxn"])) == Decimal("12.50")

    # Histórico: 6 meses del más reciente al más viejo, el actual con la comisión, el resto en cero
    history = data["history"]
    assert len(history) == 6
    assert history[0]["month"] == month
    assert Decimal(str(history[0]["commission_mxn"])) == Decimal("12.50")
    assert history[0]["sales_count"] == 2
    assert all(Decimal(str(h["commission_mxn"])) == Decimal("0") for h in history[1:])
    months = [h["month"] for h in history]
    assert months == sorted(months, reverse=True)

    # Otro mes: nada
    other = await client.get("/api/v1/analytics/commissions?period_month=2025-01", headers=headers)
    assert other.status_code == 200
    assert Decimal(str(other.json()["summary"]["earned_commission_mxn"])) == Decimal("0")
    assert other.json()["daily_breakdown"] == []

    # Cancelar la venta 2: su comisión deja de contar
    cancel = await client.post(f"/api/v1/sales/{sale2['id']}/cancel", json={"reason": "Error de captura"}, headers=headers)
    assert cancel.status_code == 200, cancel.text
    after = await client.get(f"/api/v1/analytics/commissions?period_month={month}", headers=headers)
    assert Decimal(str(after.json()["summary"]["earned_commission_mxn"])) == Decimal("10.00")
    assert after.json()["summary"]["sales_count"] == 1

    # Esquema por utilidad: 10 % de (100 − 60) = $4 en la siguiente venta
    upd2 = await client.put(
        f"/api/v1/users/{user_id}",
        json={"commission_type": "PERCENTAGE_PROFIT", "commission_rate": 10},
        headers=headers,
    )
    assert upd2.status_code == 200, upd2.text
    await _checkout(client, headers, warehouse_id, p1["id"], qty=1, price=100.00)
    final = await client.get(f"/api/v1/analytics/commissions?period_month={month}", headers=headers)
    assert Decimal(str(final.json()["summary"]["earned_commission_mxn"])) == Decimal("14.00")
    assert Decimal(str(final.json()["history"][0]["commission_mxn"])) == Decimal("14.00")


@pytest.mark.asyncio
async def test_no_commission_recorded_when_rate_is_zero(client: AsyncClient):
    """Con tasa 0 (valor por defecto) el checkout no deja asientos: el tablero queda vacío."""
    suffix = uuid.uuid4().hex[:6]
    store = await _register_store(client, suffix)
    headers = store["headers"]
    p1 = await _create_product(client, headers, f"D{suffix}", price=20.00, cost=10.00)
    warehouse_id = p1["stocks"][0]["warehouse_id"]
    shift = await client.post("/api/v1/sales/shifts/open", json={"opening_balance_mxn": 0}, headers=headers)
    assert shift.status_code == 201
    await _checkout(client, headers, warehouse_id, p1["id"], qty=1, price=20.00)

    rep = await client.get("/api/v1/analytics/commissions", headers=headers)
    assert rep.status_code == 200
    assert rep.json()["summary"]["sales_count"] == 0
    assert Decimal(str(rep.json()["summary"]["earned_commission_mxn"])) == Decimal("0")
    assert rep.json()["daily_breakdown"] == []
    assert len(rep.json()["history"]) == 6
