"""
Aislamiento por almacén — Fase 1 (Sep 2026).

El listado y el detalle de inventario responden con las existencias del
almacén de la consulta (`warehouse_stock`), el stock bajo se evalúa contra él
y quien no tiene `reports.view_advanced` queda fijo en su almacén operativo
aunque pida otro (W1, CA-W7). `total_stock` conserva la suma (W2).
"""
import uuid

import pytest
from httpx import AsyncClient


async def _register_owner(client: AsyncClient, suffix: str) -> dict:
    resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes {suffix}",
            "slug": f"wh-{suffix}",
            "full_name": "Doña Chuy",
            "email": f"chuy_wh_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert resp.status_code == 201, resp.text
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


async def _create_cashier(
    client: AsyncClient, owner: dict, suffix: str, role_name: str = "CASHIER"
) -> tuple[dict, dict]:
    roles = (await client.get("/api/v1/roles", headers=owner)).json()
    role = next(r for r in roles if r["name"] == role_name)
    email = f"{role_name.lower()}_wh_{suffix}@tienda.mx"
    created = await client.post(
        "/api/v1/users",
        json={"email": email, "password": "empleado123", "full_name": "Cajero", "role_id": role["id"]},
        headers=owner,
    )
    assert created.status_code == 201, created.text
    login = await client.post("/api/v1/auth/login", json={"email": email, "password": "empleado123"})
    assert login.status_code == 200, login.text
    return created.json(), {"Authorization": f"Bearer {login.json()['access_token']}"}


async def _two_warehouses_with_split_stock(client: AsyncClient, owner: dict) -> dict:
    """Principal con 4 piezas y Bodega con 26 del mismo producto (mínimo 5)."""
    principal = (await client.get("/api/v1/inventory/warehouses", headers=owner)).json()[0]
    bodega = await client.post(
        "/api/v1/inventory/warehouses",
        json={"name": "Bodega", "is_default": False},
        headers=owner,
    )
    assert bodega.status_code == 201, bodega.text

    product = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Coca-Cola 600ml",
            "price_mxn": "18.00",
            "initial_stock": "30",
            "min_stock_alert": "5",
            "warehouse_id": principal["id"],
        },
        headers=owner,
    )
    assert product.status_code == 201, product.text

    transfer = await client.post(
        "/api/v1/inventory/transfer-stock",
        json={
            "product_id": product.json()["id"],
            "from_warehouse_id": principal["id"],
            "to_warehouse_id": bodega.json()["id"],
            "quantity": "26",
        },
        headers=owner,
    )
    assert transfer.status_code in (200, 201), transfer.text
    return {"principal": principal["id"], "bodega": bodega.json()["id"], "product": product.json()["id"]}


@pytest.mark.asyncio
async def test_listing_reports_stock_of_the_requested_warehouse(client: AsyncClient):
    """CA-W2: el mismo producto muestra existencias distintas según el almacén."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    ids = await _two_warehouses_with_split_stock(client, owner)

    in_principal = (await client.get(
        "/api/v1/inventory/products", params={"warehouse_id": ids["principal"]}, headers=owner,
    )).json()[0]
    assert in_principal["warehouse_id"] == ids["principal"]
    assert float(in_principal["warehouse_stock"]) == 4
    assert float(in_principal["total_stock"]) == 30
    assert in_principal["is_low_stock"] is True

    in_bodega = (await client.get(
        "/api/v1/inventory/products", params={"warehouse_id": ids["bodega"]}, headers=owner,
    )).json()[0]
    assert float(in_bodega["warehouse_stock"]) == 26
    assert in_bodega["is_low_stock"] is False

    # Sin almacén: todos (el dueño puede), igual que antes
    everywhere = (await client.get("/api/v1/inventory/products", headers=owner)).json()[0]
    assert everywhere["warehouse_id"] is None
    assert float(everywhere["warehouse_stock"]) == 30
    assert everywhere["is_low_stock"] is False

    # El detalle respeta el mismo alcance
    detail = (await client.get(
        f"/api/v1/inventory/products/{ids['product']}",
        params={"warehouse_id": ids["bodega"]},
        headers=owner,
    )).json()
    assert float(detail["warehouse_stock"]) == 26


@pytest.mark.asyncio
async def test_low_stock_filter_is_relative_to_the_warehouse(client: AsyncClient):
    """CA-W4: el filtro de stock bajo responde al almacén de la consulta."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    ids = await _two_warehouses_with_split_stock(client, owner)

    low_here = (await client.get(
        "/api/v1/inventory/products",
        params={"warehouse_id": ids["principal"], "low_stock": "true"},
        headers=owner,
    )).json()
    assert [p["id"] for p in low_here] == [ids["product"]]

    low_there = (await client.get(
        "/api/v1/inventory/products",
        params={"warehouse_id": ids["bodega"], "low_stock": "true"},
        headers=owner,
    )).json()
    assert low_there == []


@pytest.mark.asyncio
async def test_cashier_asking_for_another_warehouse_gets_their_own(client: AsyncClient):
    """CA-W7: el alcance lo fuerza el servidor, no la UI."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    ids = await _two_warehouses_with_split_stock(client, owner)
    employee, cashier = await _create_cashier(client, owner, suffix)

    assigned = await client.put(
        f"/api/v1/users/{employee['id']}",
        json={"default_warehouse_id": ids["principal"]},
        headers=owner,
    )
    assert assigned.status_code == 200, assigned.text

    # Pide Bodega (o nada) y recibe su almacén
    for params in ({"warehouse_id": ids["bodega"]}, {}):
        row = (await client.get("/api/v1/inventory/products", params=params, headers=cashier)).json()[0]
        assert row["warehouse_id"] == ids["principal"]
        assert float(row["warehouse_stock"]) == 4

    detail = (await client.get(
        f"/api/v1/inventory/products/{ids['product']}",
        params={"warehouse_id": ids["bodega"]},
        headers=cashier,
    )).json()
    assert detail["warehouse_id"] == ids["principal"]

    # Y no puede cambiarse de almacén por su cuenta
    moved = await client.patch(
        "/api/v1/auth/me/warehouse", json={"warehouse_id": ids["bodega"]}, headers=cashier,
    )
    assert moved.status_code == 403

    # El dueño sí
    owner_moved = await client.patch(
        "/api/v1/auth/me/warehouse", json={"warehouse_id": ids["bodega"]}, headers=owner,
    )
    assert owner_moved.status_code == 200, owner_moved.text


@pytest.mark.asyncio
async def test_cashier_without_assignment_falls_back_to_the_main_warehouse(client: AsyncClient):
    """Sin almacén asignado, el empleado queda en el principal — nunca en "todos"."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    ids = await _two_warehouses_with_split_stock(client, owner)
    _, cashier = await _create_cashier(client, owner, suffix)

    row = (await client.get("/api/v1/inventory/products", headers=cashier)).json()[0]
    assert row["warehouse_id"] == ids["principal"]
    assert float(row["warehouse_stock"]) == 4


@pytest.mark.asyncio
@pytest.mark.parametrize("role_name", ["CASHIER", "WAREHOUSE"])
async def test_dashboard_stock_alerts_follow_the_warehouse(client: AsyncClient, role_name: str):
    """CA-W4 (D25): las alertas de stock crítico del Inicio son del almacén."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    ids = await _two_warehouses_with_split_stock(client, owner)
    employee, cashier = await _create_cashier(client, owner, suffix, role_name)

    def alert_ids(body: dict) -> list:
        data = body.get("data", body)
        return [a["product_id"] for a in data["critical_stock_alerts"]]

    here = (await client.get(
        "/api/v1/analytics/dashboard", params={"warehouse_id": ids["principal"]}, headers=owner,
    )).json()
    assert alert_ids(here) == [ids["product"]]

    there = (await client.get(
        "/api/v1/analytics/dashboard", params={"warehouse_id": ids["bodega"]}, headers=owner,
    )).json()
    assert alert_ids(there) == []

    # Un cajero de Bodega no ve la alerta de Principal aunque la pida
    await client.put(
        f"/api/v1/users/{employee['id']}", json={"default_warehouse_id": ids["bodega"]}, headers=owner,
    )
    forced = (await client.get(
        "/api/v1/analytics/dashboard", params={"warehouse_id": ids["principal"]}, headers=cashier,
    )).json()
    assert alert_ids(forced) == []


# ---------------------------------------------------------------------------
# Compras por almacén (decisiones de Eduardo, Sep 27): la orden se recibe en
# un almacén; los empleados sólo ven y crean las de su almacén, y la deuda
# con el proveedor hereda el almacén de la orden. Dueño y Encargado ven todo.
# ---------------------------------------------------------------------------

async def _order(client: AsyncClient, headers: dict, supplier_id: str, product_id: str, warehouse_id=None) -> dict:
    payload = {
        "supplier_id": supplier_id,
        "items": [{"product_id": product_id, "quantity_ordered": 10, "unit_cost_mxn": 12.00}],
    }
    if warehouse_id:
        payload["warehouse_id"] = warehouse_id
    res = await client.post("/api/v1/purchase-orders", json=payload, headers=headers)
    assert res.status_code == 201, res.text
    return res.json()


async def _receive(client: AsyncClient, headers: dict, order: dict) -> dict:
    res = await client.post(
        f"/api/v1/purchase-orders/{order['id']}/receive",
        json={"items_received": [{"purchase_order_item_id": order["items"][0]["id"], "quantity_received": 10}]},
        headers=headers,
    )
    assert res.status_code == 200, res.text
    return res.json()


@pytest.mark.asyncio
async def test_purchase_orders_and_payables_are_scoped_by_warehouse(client: AsyncClient):
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    ids = await _two_warehouses_with_split_stock(client, owner)
    employee, stocker = await _create_cashier(client, owner, suffix, "WAREHOUSE")
    await client.put(
        f"/api/v1/users/{employee['id']}", json={"default_warehouse_id": ids["principal"]}, headers=owner,
    )
    supplier = (await client.post("/api/v1/suppliers", json={"name": "Bimbo"}, headers=owner)).json()

    # El dueño elige almacén y la orden viene rotulada
    for_bodega = await _order(client, owner, supplier["id"], ids["product"], ids["bodega"])
    assert for_bodega["warehouse_id"] == ids["bodega"]
    assert for_bodega["warehouse_name"] == "Bodega"

    # El almacenista pide Bodega y compra para su almacén
    mine = await _order(client, stocker, supplier["id"], ids["product"], ids["bodega"])
    assert mine["warehouse_id"] == ids["principal"]

    # Listado: el almacenista sólo la suya; el dueño, las dos
    stocker_list = (await client.get("/api/v1/purchase-orders", headers=stocker)).json()
    assert [o["id"] for o in stocker_list] == [mine["id"]]
    owner_list = (await client.get("/api/v1/purchase-orders", headers=owner)).json()
    assert {o["id"] for o in owner_list} == {mine["id"], for_bodega["id"]}
    only_bodega = (await client.get(
        "/api/v1/purchase-orders", params={"warehouse_id": ids["bodega"]}, headers=owner,
    )).json()
    assert [o["id"] for o in only_bodega] == [for_bodega["id"]]

    # La de otra sucursal no existe para el almacenista
    assert (await client.get(f"/api/v1/purchase-orders/{for_bodega['id']}", headers=stocker)).status_code == 404

    # Recibir la de Bodega mete la mercancía en Bodega
    received = await _receive(client, owner, for_bodega)
    in_bodega = (await client.get(
        f"/api/v1/inventory/products/{ids['product']}", params={"warehouse_id": ids["bodega"]}, headers=owner,
    )).json()
    assert float(in_bodega["warehouse_stock"]) == 36
    await _receive(client, owner, mine)

    # Cuentas por pagar: cada deuda hereda el almacén de su orden
    stocker_ap = (await client.get("/api/v1/accounts-payable", headers=stocker)).json()
    assert len(stocker_ap) == 1
    owner_ap = (await client.get("/api/v1/accounts-payable", headers=owner)).json()
    assert len(owner_ap) == 2
    bodega_ap = received["account_payable"]["id"]
    assert (await client.get(f"/api/v1/accounts-payable/{bodega_ap}", headers=stocker)).status_code == 404

    stocker_summary = (await client.get("/api/v1/accounts-payable/summary", headers=stocker)).json()
    owner_summary = (await client.get("/api/v1/accounts-payable/summary", headers=owner)).json()
    assert float(stocker_summary["total_pending_mxn"]) == 120
    assert float(owner_summary["total_pending_mxn"]) == 240

    # El dueño puede acotar la deuda a un almacén; al almacenista no le sirve pedir otro
    owner_bodega = (await client.get(
        "/api/v1/accounts-payable/summary", params={"warehouse_id": ids["bodega"]}, headers=owner,
    )).json()
    assert float(owner_bodega["total_pending_mxn"]) == 120
    stocker_asks_bodega = (await client.get(
        "/api/v1/accounts-payable", params={"warehouse_id": ids["bodega"]}, headers=stocker,
    )).json()
    assert [a["id"] for a in stocker_asks_bodega] == [a["id"] for a in stocker_ap]


# ---------------------------------------------------------------------------
# Fase 2 — dinero por almacén: ventas, Inicio, Reportes y caja (CA-W5,
# CA-W6, CA-W7, CA-W9). Principal tiene 4 piezas y Bodega 26, a $18.
# ---------------------------------------------------------------------------

async def _sell(client: AsyncClient, headers: dict, warehouse_id: str, product_id: str, qty: int):
    return await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": warehouse_id,
            "items": [{"product_id": product_id, "quantity": qty, "unit_price_mxn": 18.00, "discount_mxn": 0}],
            "discount_mxn": 0,
        },
        headers=headers,
    )


def _data(body: dict) -> dict:
    return body.get("data", body)


@pytest.mark.asyncio
async def test_money_is_split_by_warehouse_and_forced_for_employees(client: AsyncClient):
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    ids = await _two_warehouses_with_split_stock(client, owner)
    employee, cashier = await _create_cashier(client, owner, suffix)
    await client.put(
        f"/api/v1/users/{employee['id']}", json={"default_warehouse_id": ids["bodega"]}, headers=owner,
    )

    # CA-W9: el turno queda con el almacén de su cajero, lo pida o no
    shift = await client.post(
        "/api/v1/sales/shifts/open",
        json={"opening_balance_mxn": 300.00, "warehouse_id": ids["principal"]},
        headers=cashier,
    )
    assert shift.status_code == 201, shift.text
    assert shift.json()["warehouse_id"] == ids["bodega"]

    # Ventas: el cajero vende en Bodega; desde Principal se le rechaza
    in_bodega = await _sell(client, cashier, ids["bodega"], ids["product"], 2)
    assert in_bodega.status_code == 201, in_bodega.text
    assert (await _sell(client, cashier, ids["principal"], ids["product"], 1)).status_code == 403
    in_principal = await _sell(client, owner, ids["principal"], ids["product"], 1)
    assert in_principal.status_code == 201, in_principal.text

    # Historial de ventas: el cajero sólo lo de Bodega, aunque pida Principal
    for params in ({}, {"warehouse_id": ids["principal"]}):
        mine = (await client.get("/api/v1/sales", params=params, headers=cashier)).json()
        items = mine["items"] if isinstance(mine, dict) else mine
        assert [s["id"] for s in items] == [in_bodega.json()["id"]]
    assert (await client.get(f"/api/v1/sales/{in_principal.json()['id']}", headers=cashier)).status_code == 404

    # Reportes (Dueño): las cifras por almacén suman el total
    def net(body: dict) -> float:
        return float(body["net_sales_mxn"])

    everything = (await client.get("/api/v1/analytics/financial-summary", params={"preset": "TODAY"}, headers=owner)).json()
    principal = (await client.get(
        "/api/v1/analytics/financial-summary", params={"preset": "TODAY", "warehouse_id": ids["principal"]}, headers=owner,
    )).json()
    bodega = (await client.get(
        "/api/v1/analytics/financial-summary", params={"preset": "TODAY", "warehouse_id": ids["bodega"]}, headers=owner,
    )).json()
    assert net(everything) == 54
    assert net(principal) == 18
    assert net(bodega) == 36
    assert net(principal) + net(bodega) == net(everything)

    # Inicio: el cajero ve lo de su almacén aunque pida otro (CA-W5, CA-W7)
    cashier_home = _data((await client.get(
        "/api/v1/analytics/dashboard", params={"warehouse_id": ids["principal"]}, headers=cashier,
    )).json())
    assert float(cashier_home["sales_metrics"]["total_revenue_mxn"]) == 36
    owner_home = _data((await client.get("/api/v1/analytics/dashboard", headers=owner)).json())
    assert float(owner_home["sales_metrics"]["total_revenue_mxn"]) == 54

    # D38: en "todos", las alertas van por almacén y rotuladas (Principal quedó en 3)
    alerts = owner_home["critical_stock_alerts"]
    assert [(a["warehouse_name"], float(a["current_stock"])) for a in alerts] == [("Almacén Principal", 3.0)]

    # Caja en capital de trabajo: el fondo del turno es de Bodega
    wc_bodega = (await client.get(
        "/api/v1/analytics/working-capital", params={"warehouse_id": ids["bodega"]}, headers=owner,
    )).json()
    wc_principal = (await client.get(
        "/api/v1/analytics/working-capital", params={"warehouse_id": ids["principal"]}, headers=owner,
    )).json()
    assert float(wc_bodega["cash_in_register_mxn"]) == 300
    assert float(wc_principal["cash_in_register_mxn"]) == 0

    # Historial de turnos: el dueño filtra; el cajero no ve turnos de otro almacén
    owner_principal_shifts = (await client.get(
        "/api/v1/sales/shifts", params={"warehouse_id": ids["principal"]}, headers=owner,
    )).json()
    assert owner_principal_shifts == []
    cashier_shifts = (await client.get(
        "/api/v1/sales/shifts", params={"warehouse_id": ids["principal"]}, headers=cashier,
    )).json()
    assert [s["id"] for s in cashier_shifts] == [shift.json()["id"]]


@pytest.mark.asyncio
async def test_cash_session_takes_the_cashier_warehouse(client: AsyncClient):
    """CA-W9 por `/cash/open-session`: el almacén lo fija el servidor."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    ids = await _two_warehouses_with_split_stock(client, owner)
    employee, cashier = await _create_cashier(client, owner, suffix)
    await client.put(
        f"/api/v1/users/{employee['id']}", json={"default_warehouse_id": ids["bodega"]}, headers=owner,
    )
    opened = await client.post(
        "/api/v1/cash/open-session",
        json={"opening_amount_mxn": 200.00, "warehouse_id": ids["principal"]},
        headers=cashier,
    )
    assert opened.status_code in (200, 201), opened.text

    by_bodega = (await client.get(
        "/api/v1/cash/sessions", params={"warehouse_id": ids["bodega"]}, headers=owner,
    )).json()
    by_principal = (await client.get(
        "/api/v1/cash/sessions", params={"warehouse_id": ids["principal"]}, headers=owner,
    )).json()
    assert by_bodega["total"] == 1
    assert by_principal["total"] == 0
