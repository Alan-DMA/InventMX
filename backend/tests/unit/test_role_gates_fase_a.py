"""
Permisos por rol — Fase A (Sep 2026).

Cubre las puertas `require_permission` que faltaban en Compras, Reportes y
configuración del Catálogo web, y la asignación de almacén operativo desde
`PUT /users/{id}` (D15). El Plan Emprendedor limita a 2 usuarios por comercio,
por eso cada test registra su propio tenant con un solo empleado.
"""
import uuid

import pytest
from httpx import AsyncClient


async def _register_owner(client: AsyncClient, suffix: str) -> dict:
    resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes {suffix}",
            "slug": f"gates-{suffix}",
            "full_name": "Doña Chuy",
            "email": f"chuy_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert resp.status_code == 201, resp.text
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


async def _create_employee(client: AsyncClient, owner_headers: dict, suffix: str, role_name: str) -> tuple[dict, dict]:
    roles = (await client.get("/api/v1/roles", headers=owner_headers)).json()
    role = next(r for r in roles if r["name"] == role_name)
    email = f"{role_name.lower()}_{suffix}@tienda.mx"
    created = await client.post(
        "/api/v1/users",
        json={
            "email": email,
            "password": "empleado123",
            "full_name": f"Empleado {role_name}",
            "role_id": role["id"],
        },
        headers=owner_headers,
    )
    assert created.status_code == 201, created.text
    login = await client.post("/api/v1/auth/login", json={"email": email, "password": "empleado123"})
    assert login.status_code == 200, login.text
    return created.json(), {"Authorization": f"Bearer {login.json()['access_token']}"}


@pytest.mark.asyncio
async def test_cashier_is_gated_out_of_purchases_reports_and_catalog_settings(client: AsyncClient):
    """CA-08: un CASHIER recibe 403 donde antes el servidor lo dejaba pasar."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    _, cashier = await _create_employee(client, owner, suffix, "CASHIER")

    # Compras: ni ver ni crear
    assert (await client.get("/api/v1/purchase-orders", headers=cashier)).status_code == 403
    assert (await client.get("/api/v1/suppliers", headers=cashier)).status_code == 403
    assert (await client.get("/api/v1/accounts-payable/summary", headers=cashier)).status_code == 403

    # Reportes: cerrados; el resumen del día y las comisiones propias siguen abiertos
    assert (await client.get("/api/v1/analytics/financial-summary", headers=cashier)).status_code == 403
    assert (await client.get("/api/v1/analytics/sales-trends", headers=cashier)).status_code == 403
    assert (await client.get("/api/v1/analytics/dashboard", headers=cashier)).status_code == 200
    assert (await client.get("/api/v1/analytics/commissions", headers=cashier)).status_code == 200

    # Configuración del catálogo web: sólo settings.manage_store
    assert (await client.get("/api/v1/catalog-settings", headers=cashier)).status_code == 403

    # El dueño conserva todo
    assert (await client.get("/api/v1/purchase-orders", headers=owner)).status_code == 200
    assert (await client.get("/api/v1/analytics/financial-summary", headers=owner)).status_code == 200
    assert (await client.get("/api/v1/catalog-settings", headers=owner)).status_code == 200

    # Los permisos que gobiernan la UI viajan en /auth/me
    me = (await client.get("/api/v1/auth/me", headers=cashier)).json()
    codes = {p["code"] for p in me["role"]["permissions"]}
    assert codes == {
        "inventory.view",
        "sales.view",
        "sales.checkout",
        "cash.view",
        "cash.open_session",
        "cash.close_session",
        "cash.manual_movement",
    }


@pytest.mark.asyncio
async def test_warehouse_role_can_buy_but_not_pay_credit(client: AsyncClient):
    """CA-08: WAREHOUSE ve y crea compras, pero no abona a proveedores (purchases.pay_credit)."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    _, warehouse = await _create_employee(client, owner, suffix, "WAREHOUSE")

    assert (await client.get("/api/v1/purchase-orders", headers=warehouse)).status_code == 200
    assert (await client.get("/api/v1/accounts-payable", headers=warehouse)).status_code == 200

    # El abono se rechaza por permiso antes de buscar la cuenta (403, no 404)
    pay = await client.post(
        f"/api/v1/accounts-payable/{uuid.uuid4()}/pay",
        json={"amount_mxn": "10.00", "payment_method": "CASH"},
        headers=warehouse,
    )
    assert pay.status_code == 403

    # Sin ventas ni reportes
    assert (await client.get("/api/v1/sales", headers=warehouse)).status_code == 403
    assert (await client.get("/api/v1/analytics/working-capital", headers=warehouse)).status_code == 403


@pytest.mark.asyncio
async def test_owner_assigns_operating_warehouse_to_employee(client: AsyncClient):
    """CA-08/CA-09 (D15): el almacén operativo del empleado se asigna desde Usuarios."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    employee, cashier = await _create_employee(client, owner, suffix, "CASHIER")

    bodega = await client.post(
        "/api/v1/inventory/warehouses",
        json={"name": "Bodega trasera", "is_default": False},
        headers=owner,
    )
    assert bodega.status_code == 201, bodega.text
    bodega_id = bodega.json()["id"]

    updated = await client.put(
        f"/api/v1/users/{employee['id']}",
        json={"default_warehouse_id": bodega_id},
        headers=owner,
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["default_warehouse_id"] == bodega_id

    # El empleado lo ve reflejado en su sesión
    me = (await client.get("/api/v1/auth/me", headers=cashier)).json()
    assert me["default_warehouse_id"] == bodega_id

    # Un almacén que no es del comercio se rechaza
    foreign = await client.put(
        f"/api/v1/users/{employee['id']}",
        json={"default_warehouse_id": str(uuid.uuid4())},
        headers=owner,
    )
    assert foreign.status_code == 404

    # El cajero no puede asignarse almacén por esta vía (settings.manage_users)
    forbidden = await client.put(
        f"/api/v1/users/{employee['id']}",
        json={"default_warehouse_id": bodega_id},
        headers=cashier,
    )
    assert forbidden.status_code == 403
