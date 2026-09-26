"""
Roles por comercio — Fase B de permisos (Sep 2026).

El dueño personaliza qué puede cada rol **en su tienda**: la primera edición de
un rol del sistema crea una copia propia (clone-on-write) y migra a los
empleados que lo tenían; "restablecer" los devuelve al estándar y borra la
copia. Nadie más reparte permisos, el rol Dueño es intocable y ningún rol se
queda sin `inventory.view`.
"""
import uuid

import pytest
from httpx import AsyncClient

CASHIER_CODES = [
    "inventory.view",
    "sales.view",
    "sales.checkout",
    "cash.view",
    "cash.open_session",
    "cash.close_session",
    "cash.manual_movement",
]


async def _register_owner(client: AsyncClient, suffix: str) -> dict:
    resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda {suffix}",
            "slug": f"roles-{suffix}",
            "full_name": "Doña Lupita",
            "email": f"lupita_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert resp.status_code == 201, resp.text
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


async def _roles(client: AsyncClient, headers: dict) -> list:
    resp = await client.get("/api/v1/roles", headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()


async def _role_named(client: AsyncClient, headers: dict, name: str) -> dict:
    return next(r for r in await _roles(client, headers) if r["name"] == name)


async def _create_employee(
    client: AsyncClient, owner: dict, suffix: str, role_id: str, who: str = "cajero"
) -> tuple[dict, dict]:
    email = f"{who}_{suffix}@tienda.mx"
    created = await client.post(
        "/api/v1/users",
        json={
            "email": email,
            "password": "empleado123",
            "full_name": f"Empleado {who}",
            "role_id": role_id,
        },
        headers=owner,
    )
    assert created.status_code == 201, created.text
    login = await client.post(
        "/api/v1/auth/login", json={"email": email, "password": "empleado123"}
    )
    assert login.status_code == 200, login.text
    return created.json(), {"Authorization": f"Bearer {login.json()['access_token']}"}


@pytest.mark.asyncio
async def test_first_edit_clones_the_role_and_migrates_employees(client: AsyncClient):
    """CA-B1/CA-B2/CA-B3: clone-on-write, migración, y el cambio surte efecto."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    cashier_role = await _role_named(client, owner, "CASHIER")
    assert cashier_role["tenant_id"] is None

    employee, cashier = await _create_employee(
        client, owner, suffix, cashier_role["id"]
    )

    # De fábrica el cajero ve el historial de ventas
    assert (await client.get("/api/v1/sales", headers=cashier)).status_code == 200

    # El dueño le quita `sales.view`
    sin_historial = [c for c in CASHIER_CODES if c != "sales.view"]
    resp = await client.put(
        f"/api/v1/roles/{cashier_role['id']}/permissions",
        json={"permissions": sin_historial},
        headers=owner,
    )
    assert resp.status_code == 200, resp.text
    propio = resp.json()
    assert propio["tenant_id"] is not None
    assert propio["id"] != cashier_role["id"]
    assert {p["code"] for p in propio["permissions"]} == set(sin_historial)

    # El empleado quedó en la copia y el servidor ya le cierra la puerta
    me = (await client.get("/api/v1/auth/me", headers=cashier)).json()
    assert me["role_id"] == propio["id"]
    assert (await client.get("/api/v1/sales", headers=cashier)).status_code == 403
    # Lo que conserva sigue abierto
    assert (
        await client.get("/api/v1/inventory/products", headers=cashier)
    ).status_code == 200

    # El listado sigue mostrando cuatro roles: la copia sustituye al estándar
    roles = await _roles(client, owner)
    assert sorted(r["name"] for r in roles) == ["ADMIN", "CASHIER", "OWNER", "WAREHOUSE"]
    assert next(r for r in roles if r["name"] == "CASHIER")["id"] == propio["id"]

    # CA-B2: una segunda edición no crea otra copia
    otra = await client.put(
        f"/api/v1/roles/{propio['id']}/permissions",
        json={"permissions": CASHIER_CODES},
        headers=owner,
    )
    assert otra.status_code == 200
    assert otra.json()["id"] == propio["id"]
    roles = await _roles(client, owner)
    assert len([r for r in roles if r["name"] == "CASHIER"]) == 1
    # Y el permiso devuelto vuelve a funcionar
    assert (await client.get("/api/v1/sales", headers=cashier)).status_code == 200
    assert employee["id"] == me["id"]


@pytest.mark.asyncio
async def test_customizing_the_standard_role_twice_leaves_one_copy(
    client: AsyncClient,
):
    """
    Idempotencia del clone-on-write (QA de Eduardo, Sep 23).

    Si se pide personalizar el rol **estándar** dos veces —un reintento tras un
    error, o dos toques seguidos— debe quedar una sola copia: con dos, el
    listado mostraba dos "Almacenista" y el dueño no sabía cuál asignar.
    """
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    estandar = await _role_named(client, owner, "WAREHOUSE")

    primera = await client.put(
        f"/api/v1/roles/{estandar['id']}/permissions",
        json={"permissions": ["inventory.view", "inventory.create"]},
        headers=owner,
    )
    assert primera.status_code == 200, primera.text

    # Se insiste sobre el id del rol estándar, como haría una pantalla que
    # todavía no recargó la lista
    segunda = await client.put(
        f"/api/v1/roles/{estandar['id']}/permissions",
        json={"permissions": ["inventory.view", "purchases.view"]},
        headers=owner,
    )
    assert segunda.status_code == 200, segunda.text
    assert segunda.json()["id"] == primera.json()["id"]

    roles = await _roles(client, owner)
    assert [r["name"] for r in roles].count("WAREHOUSE") == 1
    assert {p["code"] for p in (await _role_named(client, owner, "WAREHOUSE"))["permissions"]} == {
        "inventory.view",
        "purchases.view",
    }


@pytest.mark.asyncio
async def test_reset_returns_employees_to_the_standard_role(client: AsyncClient):
    """CA-B4: restablecer borra la copia y devuelve a los empleados."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    cashier_role = await _role_named(client, owner, "CASHIER")
    _, cashier = await _create_employee(client, owner, suffix, cashier_role["id"])

    propio = (
        await client.put(
            f"/api/v1/roles/{cashier_role['id']}/permissions",
            json={"permissions": ["inventory.view"]},
            headers=owner,
        )
    ).json()
    assert (await client.get("/api/v1/sales", headers=cashier)).status_code == 403

    restablecido = await client.delete(
        f"/api/v1/roles/{propio['id']}", headers=owner
    )
    assert restablecido.status_code == 200, restablecido.text
    assert restablecido.json()["id"] == cashier_role["id"]
    assert restablecido.json()["tenant_id"] is None

    # El empleado volvió al estándar y recuperó lo suyo
    me = (await client.get("/api/v1/auth/me", headers=cashier)).json()
    assert me["role_id"] == cashier_role["id"]
    assert (await client.get("/api/v1/sales", headers=cashier)).status_code == 200

    roles = await _roles(client, owner)
    assert all(r["tenant_id"] is None for r in roles)


@pytest.mark.asyncio
async def test_only_the_owner_may_hand_out_permissions(client: AsyncClient):
    """CA-B5: ni el Encargado ni el Cajero reparten permisos."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    cashier_role = await _role_named(client, owner, "CASHIER")
    admin_role = await _role_named(client, owner, "ADMIN")

    _, encargado = await _create_employee(
        client, owner, suffix, admin_role["id"], who="encargado"
    )

    # El Encargado tiene settings.manage_users (ve la lista de empleados)…
    assert (await client.get("/api/v1/users", headers=encargado)).status_code == 200
    # …pero no puede repartir permisos
    forbidden = await client.put(
        f"/api/v1/roles/{cashier_role['id']}/permissions",
        json={"permissions": CASHIER_CODES},
        headers=encargado,
    )
    assert forbidden.status_code == 403
    assert (
        await client.delete(f"/api/v1/roles/{cashier_role['id']}", headers=encargado)
    ).status_code == 403


@pytest.mark.asyncio
async def test_owner_role_and_minimum_permission_are_protected(client: AsyncClient):
    """CA-B6/CA-B7: el rol Dueño no se edita y nadie se queda sin inventory.view."""
    suffix = uuid.uuid4().hex[:6]
    owner = await _register_owner(client, suffix)
    owner_role = await _role_named(client, owner, "OWNER")
    cashier_role = await _role_named(client, owner, "CASHIER")

    protegido = await client.put(
        f"/api/v1/roles/{owner_role['id']}/permissions",
        json={"permissions": ["inventory.view"]},
        headers=owner,
    )
    assert protegido.status_code == 400
    assert "Dueño" in protegido.json()["error"]["message"]

    sin_minimo = await client.put(
        f"/api/v1/roles/{cashier_role['id']}/permissions",
        json={"permissions": ["sales.checkout"]},
        headers=owner,
    )
    assert sin_minimo.status_code == 400
    assert "inventory.view" in sin_minimo.json()["error"]["message"]

    inventado = await client.put(
        f"/api/v1/roles/{cashier_role['id']}/permissions",
        json={"permissions": ["inventory.view", "ventas.cobrar"]},
        headers=owner,
    )
    assert inventado.status_code == 400
    assert "ventas.cobrar" in inventado.json()["error"]["message"]

    # Ninguno de los rechazos dejó una copia a medias
    roles = await _roles(client, owner)
    assert all(r["tenant_id"] is None for r in roles)


@pytest.mark.asyncio
async def test_a_custom_role_never_reaches_another_store(client: AsyncClient):
    """CA-B9: el aislamiento entre comercios, ahora también con RLS en roles."""
    suffix_a = uuid.uuid4().hex[:6]
    suffix_b = uuid.uuid4().hex[:6]
    tienda_a = await _register_owner(client, suffix_a)
    tienda_b = await _register_owner(client, suffix_b)

    cashier_a = await _role_named(client, tienda_a, "CASHIER")
    propio_a = (
        await client.put(
            f"/api/v1/roles/{cashier_a['id']}/permissions",
            json={"permissions": ["inventory.view", "sales.checkout"]},
            headers=tienda_a,
        )
    ).json()

    # La tienda B sigue viendo los cuatro roles estándar, sin rastro del ajeno
    roles_b = await _roles(client, tienda_b)
    assert all(r["tenant_id"] is None for r in roles_b)
    assert propio_a["id"] not in [r["id"] for r in roles_b]

    # Y no puede tocarlo ni borrarlo
    assert (
        await client.put(
            f"/api/v1/roles/{propio_a['id']}/permissions",
            json={"permissions": ["inventory.view"]},
            headers=tienda_b,
        )
    ).status_code == 404
    assert (
        await client.delete(f"/api/v1/roles/{propio_a['id']}", headers=tienda_b)
    ).status_code == 404

    # El de A sigue intacto
    cashier_a_despues = await _role_named(client, tienda_a, "CASHIER")
    assert cashier_a_despues["id"] == propio_a["id"]
    assert {p["code"] for p in cashier_a_despues["permissions"]} == {
        "inventory.view",
        "sales.checkout",
    }
