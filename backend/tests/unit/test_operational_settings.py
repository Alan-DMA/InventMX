"""
Ajustes operativos contra el backend real (Sep 2026, D7–D9).

- D9: cambiar contraseña exige la actual; mínimo 8; la sesión sigue abierta.
- D7: baja lógica de almacén sólo vacío y sin pendientes, cada regla con su
  motivo (422); reactivar; un almacén inactivo no opera.
- D7b: "Hacer principal" — el principal no se da de baja hasta elegir otro.
- D8: una categoría con productos no se borra; renombrar es único.
"""
import uuid

import pytest
from httpx import AsyncClient


async def _register_owner(client: AsyncClient, suffix: str) -> dict:
    resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Ajustes {suffix}",
            "slug": f"ajustes-{suffix}",
            "full_name": "Doña Chuy",
            "email": f"chuy_ajustes_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert resp.status_code == 201, resp.text
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


async def _create_employee(
    client: AsyncClient, owner: dict, suffix: str, role_name: str = "CASHIER"
) -> tuple[dict, dict]:
    roles = (await client.get("/api/v1/roles", headers=owner)).json()
    role = next(r for r in roles if r["name"] == role_name)
    email = f"{role_name.lower()}_ajustes_{suffix}@tienda.mx"
    created = await client.post(
        "/api/v1/users",
        json={"email": email, "password": "empleado123", "full_name": "Pepe Cajero", "role_id": role["id"]},
        headers=owner,
    )
    assert created.status_code == 201, created.text
    login = await client.post("/api/v1/auth/login", json={"email": email, "password": "empleado123"})
    assert login.status_code == 200, login.text
    return created.json(), {"Authorization": f"Bearer {login.json()['access_token']}"}


async def _principal_and_bodega(client: AsyncClient, owner: dict) -> tuple[str, str]:
    principal = (await client.get("/api/v1/inventory/warehouses", headers=owner)).json()[0]
    bodega = await client.post(
        "/api/v1/inventory/warehouses",
        json={"name": "Bodega", "is_default": False},
        headers=owner,
    )
    assert bodega.status_code == 201, bodega.text
    return principal["id"], bodega.json()["id"]


def _detail(resp) -> str:
    body = resp.json()
    return body.get("detail") or body.get("error", {}).get("message", "")


def _by_id(items: list, item_id: str) -> dict:
    return next(i for i in items if i["id"] == item_id)


# -----------------------------------------------------------------------------
# D9 — Contraseña
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_change_password_requires_current_and_keeps_session(client: AsyncClient):
    """CA-A1: con la actual cambia; la sesión sigue; la vieja deja de servir."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    email = f"chuy_ajustes_{suffix}@tienda.mx"

    wrong = await client.post(
        "/api/v1/auth/change-password",
        json={"current_password": "equivocada", "new_password": "nuevaClave99"},
        headers=owner,
    )
    assert wrong.status_code == 400
    assert "actual" in _detail(wrong)

    short = await client.post(
        "/api/v1/auth/change-password",
        json={"current_password": "password123", "new_password": "corta"},
        headers=owner,
    )
    assert short.status_code == 422

    ok = await client.post(
        "/api/v1/auth/change-password",
        json={"current_password": "password123", "new_password": "nuevaClave99"},
        headers=owner,
    )
    assert ok.status_code == 204, ok.text

    # La sesión sigue abierta con el mismo token
    assert (await client.get("/api/v1/auth/me", headers=owner)).status_code == 200

    old_login = await client.post("/api/v1/auth/login", json={"email": email, "password": "password123"})
    assert old_login.status_code == 401
    new_login = await client.post("/api/v1/auth/login", json={"email": email, "password": "nuevaClave99"})
    assert new_login.status_code == 200


# -----------------------------------------------------------------------------
# D7 — Almacenes
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_rename_warehouse_is_unique_and_listing_reports_state(client: AsyncClient):
    """CA-A2: renombrar se refleja en el listado; el nombre es único sin mayúsculas."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    principal, bodega = await _principal_and_bodega(client, owner)

    renamed = await client.put(
        f"/api/v1/inventory/warehouses/{bodega}", json={"name": "Bodega Norte"}, headers=owner,
    )
    assert renamed.status_code == 200, renamed.text
    assert renamed.json()["name"] == "Bodega Norte"

    dup = await client.put(
        f"/api/v1/inventory/warehouses/{bodega}", json={"name": "almacén principal"}, headers=owner,
    )
    assert dup.status_code == 409

    dup_create = await client.post(
        "/api/v1/inventory/warehouses", json={"name": "BODEGA NORTE", "is_default": False}, headers=owner,
    )
    assert dup_create.status_code == 409

    listing = (await client.get("/api/v1/inventory/warehouses", headers=owner)).json()
    assert _by_id(listing, bodega)["name"] == "Bodega Norte"
    assert all(w["is_active"] is True for w in listing)
    assert _by_id(listing, principal)["is_default"] is True


@pytest.mark.asyncio
async def test_principal_cannot_be_deactivated_until_another_is_made_default(client: AsyncClient):
    """D7b / CA-A4: el principal se protege; "Hacer principal" deja uno solo."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    principal, bodega = await _principal_and_bodega(client, owner)

    refused = await client.delete(f"/api/v1/inventory/warehouses/{principal}", headers=owner)
    assert refused.status_code == 422
    assert "principal" in _detail(refused)

    made = await client.post(f"/api/v1/inventory/warehouses/{bodega}/make-default", headers=owner)
    assert made.status_code == 200, made.text
    assert made.json()["is_default"] is True

    listing = (await client.get("/api/v1/inventory/warehouses", headers=owner)).json()
    assert [w["id"] for w in listing if w["is_default"]] == [bodega]

    # El antiguo principal ya se puede dar de baja (vacío: el producto nunca se creó ahí)
    gone = await client.delete(f"/api/v1/inventory/warehouses/{principal}", headers=owner)
    assert gone.status_code == 200, gone.text
    assert gone.json()["is_active"] is False


@pytest.mark.asyncio
async def test_deactivate_refuses_with_stock(client: AsyncClient):
    """CA-A3: con existencias no se da de baja."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    principal, bodega = await _principal_and_bodega(client, owner)
    product = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Coca-Cola 600ml", "price_mxn": "18.00", "initial_stock": "10", "warehouse_id": bodega},
        headers=owner,
    )
    assert product.status_code == 201, product.text

    refused = await client.delete(f"/api/v1/inventory/warehouses/{bodega}", headers=owner)
    assert refused.status_code == 422
    assert "existencias" in _detail(refused)


@pytest.mark.asyncio
async def test_deactivate_refuses_when_someone_operates_there(client: AsyncClient):
    """CA-A3: si alguien activo opera ahí, se nombra en el motivo."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    principal, bodega = await _principal_and_bodega(client, owner)
    cashier, _ = await _create_employee(client, owner, suffix)
    assigned = await client.put(
        f"/api/v1/users/{cashier['id']}", json={"default_warehouse_id": bodega}, headers=owner,
    )
    assert assigned.status_code == 200, assigned.text

    refused = await client.delete(f"/api/v1/inventory/warehouses/{bodega}", headers=owner)
    assert refused.status_code == 422
    assert "Pepe Cajero" in _detail(refused)


@pytest.mark.asyncio
async def test_deactivate_refuses_with_open_shift(client: AsyncClient):
    """CA-A3: un turno de caja abierto en el almacén lo impide."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    principal, bodega = await _principal_and_bodega(client, owner)

    # El dueño abre turno parado en la Bodega y vuelve al principal
    await client.patch("/api/v1/auth/me/warehouse", json={"warehouse_id": bodega}, headers=owner)
    opened = await client.post(
        "/api/v1/sales/shifts/open", json={"opening_balance_mxn": 500.00}, headers=owner,
    )
    assert opened.status_code == 201, opened.text
    await client.patch("/api/v1/auth/me/warehouse", json={"warehouse_id": principal}, headers=owner)

    refused = await client.delete(f"/api/v1/inventory/warehouses/{bodega}", headers=owner)
    assert refused.status_code == 422
    assert "turno" in _detail(refused)


@pytest.mark.asyncio
async def test_deactivate_refuses_with_pending_purchases(client: AsyncClient):
    """CA-A3: compras sin recibir para el almacén lo impiden."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    principal, bodega = await _principal_and_bodega(client, owner)
    supplier = await client.post(
        "/api/v1/suppliers", json={"name": "Bimbo", "rfc": f"BIM{suffix[:6].upper()}AAA"}, headers=owner,
    )
    assert supplier.status_code == 201, supplier.text
    product = await client.post(
        "/api/v1/inventory/products", json={"name": "Pan Blanco", "price_mxn": "45.00"}, headers=owner,
    )
    order = await client.post(
        "/api/v1/purchase-orders",
        json={
            "supplier_id": supplier.json()["id"],
            "warehouse_id": bodega,
            "items": [{"product_id": product.json()["id"], "quantity_ordered": 10, "unit_cost_mxn": 30.00}],
        },
        headers=owner,
    )
    assert order.status_code == 201, order.text

    refused = await client.delete(f"/api/v1/inventory/warehouses/{bodega}", headers=owner)
    assert refused.status_code == 422
    assert "sin recibir" in _detail(refused)


@pytest.mark.asyncio
async def test_inactive_warehouse_does_not_operate_and_can_be_reactivated(client: AsyncClient):
    """CA-A3/CA-A4: dado de baja no recibe traslados, ventas, compras ni personas; se reactiva."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    principal, bodega = await _principal_and_bodega(client, owner)
    product = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Sabritas 45g", "price_mxn": "20.00", "initial_stock": "5", "warehouse_id": principal},
        headers=owner,
    )
    product_id = product.json()["id"]

    gone = await client.delete(f"/api/v1/inventory/warehouses/{bodega}", headers=owner)
    assert gone.status_code == 200, gone.text
    listing = (await client.get("/api/v1/inventory/warehouses", headers=owner)).json()
    assert _by_id(listing, bodega)["is_active"] is False

    transfer = await client.post(
        "/api/v1/inventory/transfer-stock",
        json={"product_id": product_id, "from_warehouse_id": principal, "to_warehouse_id": bodega, "quantity": "1"},
        headers=owner,
    )
    assert transfer.status_code == 422

    checkout = await client.post(
        "/api/v1/sales/checkout",
        json={
            "warehouse_id": bodega,
            "items": [{"product_id": product_id, "quantity": 1, "unit_price_mxn": 20.00, "discount_mxn": 0}],
            "discount_mxn": 0,
        },
        headers=owner,
    )
    assert checkout.status_code == 422

    operate = await client.patch("/api/v1/auth/me/warehouse", json={"warehouse_id": bodega}, headers=owner)
    assert operate.status_code == 422

    cashier, _ = await _create_employee(client, owner, suffix)
    assign = await client.put(
        f"/api/v1/users/{cashier['id']}", json={"default_warehouse_id": bodega}, headers=owner,
    )
    assert assign.status_code == 422

    make_default = await client.post(f"/api/v1/inventory/warehouses/{bodega}/make-default", headers=owner)
    assert make_default.status_code == 422

    back = await client.post(f"/api/v1/inventory/warehouses/{bodega}/activate", headers=owner)
    assert back.status_code == 200
    assert back.json()["is_active"] is True
    transfer_again = await client.post(
        "/api/v1/inventory/transfer-stock",
        json={"product_id": product_id, "from_warehouse_id": principal, "to_warehouse_id": bodega, "quantity": "1"},
        headers=owner,
    )
    assert transfer_again.status_code in (200, 201), transfer_again.text


@pytest.mark.asyncio
async def test_warehouse_and_category_admin_requires_manage_store(client: AsyncClient):
    """Puerta: renombrar/baja/principal/categorías son de Preferencias operativas."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    principal, bodega = await _principal_and_bodega(client, owner)
    _, cashier = await _create_employee(client, owner, suffix)
    category = await client.post("/api/v1/inventory/categories", json={"name": "Dulces"}, headers=owner)

    assert (await client.put(
        f"/api/v1/inventory/warehouses/{bodega}", json={"name": "X"}, headers=cashier,
    )).status_code == 403
    assert (await client.delete(f"/api/v1/inventory/warehouses/{bodega}", headers=cashier)).status_code == 403
    assert (await client.post(
        f"/api/v1/inventory/warehouses/{bodega}/make-default", headers=cashier,
    )).status_code == 403
    assert (await client.delete(
        f"/api/v1/inventory/categories/{category.json()['id']}", headers=cashier,
    )).status_code == 403


# -----------------------------------------------------------------------------
# D8 — Categorías
# -----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_categories_report_product_count_rename_and_delete_rules(client: AsyncClient):
    """CA-A2/CA-A5/CA-A6: conteo en el listado, renombrar único, no se borra con productos."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    bebidas = (await client.post("/api/v1/inventory/categories", json={"name": "Bebidas"}, headers=owner)).json()
    vacia = (await client.post("/api/v1/inventory/categories", json={"name": "Otros"}, headers=owner)).json()
    product = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Jarrito 600ml", "price_mxn": "17.00", "category_id": bebidas["id"]},
        headers=owner,
    )
    assert product.status_code == 201, product.text

    listing = (await client.get("/api/v1/inventory/categories", headers=owner)).json()
    assert _by_id(listing, bebidas["id"])["product_count"] == 1
    assert _by_id(listing, vacia["id"])["product_count"] == 0

    renamed = await client.put(
        f"/api/v1/inventory/categories/{bebidas['id']}", json={"name": "Refrescos"}, headers=owner,
    )
    assert renamed.status_code == 200, renamed.text
    assert renamed.json()["name"] == "Refrescos"
    assert renamed.json()["product_count"] == 1
    detail = (await client.get(f"/api/v1/inventory/products/{product.json()['id']}", headers=owner)).json()
    assert detail["category_name"] == "Refrescos"

    dup = await client.put(
        f"/api/v1/inventory/categories/{vacia['id']}", json={"name": "refrescos"}, headers=owner,
    )
    assert dup.status_code == 409

    in_use = await client.delete(f"/api/v1/inventory/categories/{bebidas['id']}", headers=owner)
    assert in_use.status_code == 422
    assert "1 producto" in _detail(in_use)
    # El producto sigue ahí y en su categoría
    still = (await client.get(f"/api/v1/inventory/products/{product.json()['id']}", headers=owner))
    assert still.status_code == 200
    assert still.json()["category_id"] == bebidas["id"]

    removed = await client.delete(f"/api/v1/inventory/categories/{vacia['id']}", headers=owner)
    assert removed.status_code == 204
    listing = (await client.get("/api/v1/inventory/categories", headers=owner)).json()
    assert vacia["id"] not in [c["id"] for c in listing]
