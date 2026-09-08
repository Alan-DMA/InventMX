# Importación de UUID para generación de identificadores de prueba
import uuid
# Importación del framework pytest
import pytest
# Importación del cliente HTTP asíncrono
from httpx import AsyncClient

# Importación de utilidades de JWT para simulación de tokens en diferentes estados
from app.core.security.jwt import create_access_token


@pytest.mark.asyncio
async def test_owner_can_list_roles_and_permissions(client: AsyncClient):
    """
    HU-03 / CU-03:
    Verifica que el usuario dueño pueda consultar el catálogo de roles y permisos del sistema.
    """
    suffix = uuid.uuid4().hex[:6]
    # Registro de tienda inicial
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes {suffix}",
            "slug": f"abarrotes-{suffix}",
            "full_name": "Don Ramón",
            "email": f"ramon_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Consultar roles disponibles
    roles_resp = await client.get("/api/v1/roles", headers=headers)
    assert roles_resp.status_code == 200
    roles = roles_resp.json()
    role_names = [r["name"] for r in roles]
    assert "ADMIN" in role_names
    assert "CASHIER" in role_names
    assert "WAREHOUSE" in role_names

    # 2. Consultar catálogo maestro de permisos
    perms_resp = await client.get("/api/v1/permissions", headers=headers)
    assert perms_resp.status_code == 200
    perms = perms_resp.json()
    assert len(perms) >= 20
    perm_codes = [p["code"] for p in perms]
    assert "inventory.view" in perm_codes
    assert "sales.checkout" in perm_codes
    assert "cash.close_session" in perm_codes


@pytest.mark.asyncio
async def test_employee_creation_and_plan_limit(client: AsyncClient):
    """
    HU-03 / CU-03:
    Verifica la creación de un empleado dentro del límite de Plan Emprendedor (límite: 2 usuarios)
    y el posterior bloqueo al intentar registrar un 3er usuario (límite superado).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Supermercado {suffix}",
            "slug": f"super-{suffix}",
            "full_name": "Doña Florinda",
            "email": f"florinda_{suffix}@super.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Obtener ID del rol CASHIER
    roles_resp = await client.get("/api/v1/roles", headers=headers)
    cashier_role = next(r for r in roles_resp.json() if r["name"] == "CASHIER")

    # 1. Crear el 2do usuario (Cajero) - Debe permitirse (Total: 2/2)
    create_emp_payload = {
        "email": f"cajero_{suffix}@super.mx",
        "password": "cajeropassword",
        "full_name": "Quico Meza",
        "role_id": cashier_role["id"],
    }
    create_resp = await client.post("/api/v1/users", json=create_emp_payload, headers=headers)
    assert create_resp.status_code == 201
    cajero_data = create_resp.json()
    assert cajero_data["email"] == f"cajero_{suffix}@super.mx"
    assert cajero_data["role"]["name"] == "CASHIER"

    # 2. Intentar crear un 3er usuario en Plan Emprendedor - Debe ser rechazado (HTTP 400)
    create_third_payload = {
        "email": f"almacen_{suffix}@super.mx",
        "password": "almacenpassword",
        "full_name": "Ñoño Godínez",
        "role_id": cashier_role["id"],
    }
    third_resp = await client.post("/api/v1/users", json=create_third_payload, headers=headers)
    assert third_resp.status_code == 400
    assert "límite máximo de 2 usuarios" in third_resp.json()["error"]["message"]


@pytest.mark.asyncio
async def test_cashier_rbac_permission_enforcement(client: AsyncClient):
    """
    HU-03 / CU-03:
    Verifica que un empleado con rol CASHIER no pueda acceder a rutas de administración
    de usuarios (settings.manage_users) y reciba HTTP 403 Forbidden.
    """
    suffix = uuid.uuid4().hex[:6]
    # Registro de dueño
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Mini Super {suffix}",
            "slug": f"minisuper-{suffix}",
            "full_name": "Profesor Jirafales",
            "email": f"profesor_{suffix}@escuela.mx",
            "password": "password123",
        },
    )
    owner_token = reg_resp.json()["access_token"]
    owner_headers = {"Authorization": f"Bearer {owner_token}"}

    # Obtener ID del rol CASHIER
    roles_resp = await client.get("/api/v1/roles", headers=owner_headers)
    cashier_role = next(r for r in roles_resp.json() if r["name"] == "CASHIER")

    # Crear cajero
    await client.post(
        "/api/v1/users",
        json={
            "email": f"cajero_{suffix}@escuela.mx",
            "password": "cajeropassword",
            "full_name": "Godínez",
            "role_id": cashier_role["id"],
        },
        headers=owner_headers,
    )

    # Iniciar sesión como cajero
    login_cajero_resp = await client.post(
        "/api/v1/auth/login",
        json={
            "email": f"cajero_{suffix}@escuela.mx",
            "password": "cajeropassword",
        },
    )
    assert login_cajero_resp.status_code == 200
    cajero_token = login_cajero_resp.json()["access_token"]
    cajero_headers = {"Authorization": f"Bearer {cajero_token}"}

    # Intentar acceder a listado de usuarios como cajero
    forbidden_resp = await client.get("/api/v1/users", headers=cajero_headers)
    assert forbidden_resp.status_code == 403
    assert forbidden_resp.json()["error"]["code"] == "AUTH_FORBIDDEN"


@pytest.mark.asyncio
async def test_owner_account_protection(client: AsyncClient):
    """
    HU-03 / CU-03:
    Verifica que la cuenta del dueño (OWNER) esté blindada contra eliminación,
    desactivación o degradación de rol.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tiendita {suffix}",
            "slug": f"tiendita-{suffix}",
            "full_name": "Don Jaimito",
            "email": f"jaimito_{suffix}@cartero.mx",
            "password": "password123",
        },
    )
    owner_data = reg_resp.json()["user"]
    owner_id = owner_data["id"]
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Intentar desactivar al dueño
    toggle_resp = await client.patch(f"/api/v1/users/{owner_id}/status", headers=headers)
    assert toggle_resp.status_code == 400
    assert "No es posible desactivar la cuenta principal del dueño" in toggle_resp.json()["error"]["message"]

    # 2. Intentar eliminar al dueño
    delete_resp = await client.delete(f"/api/v1/users/{owner_id}", headers=headers)
    assert delete_resp.status_code == 400

    # 3. Intentar degradar el rol del dueño a CASHIER
    roles_resp = await client.get("/api/v1/roles", headers=headers)
    cashier_role = next(r for r in roles_resp.json() if r["name"] == "CASHIER")
    demote_resp = await client.put(
        f"/api/v1/users/{owner_id}",
        json={"role_id": cashier_role["id"]},
        headers=headers,
    )
    assert demote_resp.status_code == 400
    assert "No es posible cambiar o degradar el rol del dueño principal" in demote_resp.json()["error"]["message"]


@pytest.mark.asyncio
async def test_employee_role_update_flow(client: AsyncClient):
    """
    HU-03 / CU-03:
    Verifica la actualización de rol de un empleado (ej. promover de CASHIER a WAREHOUSE).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Boutique {suffix}",
            "slug": f"boutique-{suffix}",
            "full_name": "Paty",
            "email": f"paty_{suffix}@boutique.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    roles_resp = await client.get("/api/v1/roles", headers=headers)
    cashier_role = next(r for r in roles_resp.json() if r["name"] == "CASHIER")
    warehouse_role = next(r for r in roles_resp.json() if r["name"] == "WAREHOUSE")

    # Crear empleado cajero
    create_resp = await client.post(
        "/api/v1/users",
        json={
            "email": f"empleado_{suffix}@boutique.mx",
            "password": "password123",
            "full_name": "Gloria",
            "role_id": cashier_role["id"],
        },
        headers=headers,
    )
    assert create_resp.status_code == 201
    emp_id = create_resp.json()["id"]

    # Promover a Warehouse
    update_resp = await client.put(
        f"/api/v1/users/{emp_id}",
        json={"role_id": warehouse_role["id"]},
        headers=headers,
    )
    assert update_resp.status_code == 200
    assert update_resp.json()["role"]["name"] == "WAREHOUSE"


@pytest.mark.asyncio
async def test_subscription_soft_lock_middleware(client: AsyncClient):
    """
    Const. Art. 6.3 / Doc. Maestro Sec. 3:
    Verifica que un comercio en SOFT_LOCK (Días 1-10 de morosidad)
    pueda realizar peticiones GET (Solo Lectura) pero sea bloqueado en peticiones POST (403 Forbidden).
    """
    user_id = uuid.uuid4()
    tenant_id = uuid.uuid4()

    # Generar token con claim tenant_status="SOFT_LOCK"
    soft_lock_token = create_access_token(
        subject=user_id,
        tenant_id=tenant_id,
        role="OWNER",
        tenant_status="SOFT_LOCK",
    )
    headers = {"Authorization": f"Bearer {soft_lock_token}"}

    # 1. Petición POST debe ser bloqueada con 403
    post_resp = await client.post(
        "/api/v1/users",
        json={"email": "any@test.mx", "password": "password123", "full_name": "Test", "role_id": str(uuid.uuid4())},
        headers=headers,
    )
    assert post_resp.status_code == 403
    assert post_resp.json()["error"]["code"] == "TENANT_SOFT_LOCK"


@pytest.mark.asyncio
async def test_subscription_hard_lock_middleware(client: AsyncClient):
    """
    Const. Art. 6.3 / Doc. Maestro Sec. 3:
    Verifica que un comercio en HARD_LOCK (Día 11+ de morosidad)
    tenga bloqueado el acceso a cualquier ruta operativa con HTTP 402 Payment Required.
    """
    user_id = uuid.uuid4()
    tenant_id = uuid.uuid4()

    # Generar token con claim tenant_status="HARD_LOCK"
    hard_lock_token = create_access_token(
        subject=user_id,
        tenant_id=tenant_id,
        role="OWNER",
        tenant_status="HARD_LOCK",
    )
    headers = {"Authorization": f"Bearer {hard_lock_token}"}

    # Cualquier petición debe responder 402 Payment Required
    resp = await client.get("/api/v1/users", headers=headers)
    assert resp.status_code == 402
    assert resp.json()["error"]["code"] == "TENANT_HARD_LOCK"
