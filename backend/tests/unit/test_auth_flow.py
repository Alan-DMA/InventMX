import uuid
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_register_and_login_flow(client: AsyncClient):
    """
    Verifica el flujo completo de registro de un nuevo comercio (Tenant)
    y autenticación del usuario dueño (Owner).
    """
    unique_suffix = uuid.uuid4().hex[:6]
    store_name = f"Tienda La Esquina {unique_suffix}"
    slug = f"la-esquina-{unique_suffix}"
    email = f"owner_{unique_suffix}@laesquina.mx"
    password = "password123"

    # 1. Registro del comercio
    register_payload = {
        "store_name": store_name,
        "slug": slug,
        "full_name": "Don Roberto",
        "email": email,
        "password": password,
    }
    reg_response = await client.post("/api/v1/auth/register", json=register_payload)
    assert reg_response.status_code == 201
    reg_data = reg_response.json()
    assert "access_token" in reg_data
    assert "refresh_token" in reg_data
    assert reg_data["user"]["email"] == email
    assert reg_data["tenant"]["slug"] == slug
    assert reg_data["tenant"]["plan_id"] == "EMPRENDEDOR"

    access_token = reg_data["access_token"]
    refresh_token = reg_data["refresh_token"]

    # 2. Obtener perfil /me con el Access Token
    headers = {"Authorization": f"Bearer {access_token}"}
    me_response = await client.get("/api/v1/auth/me", headers=headers)
    assert me_response.status_code == 200
    me_data = me_response.json()
    assert me_data["email"] == email
    assert me_data["full_name"] == "Don Roberto"
    assert me_data["role"]["name"] == "OWNER"

    # 3. Iniciar sesión nuevamente con las credenciales
    login_payload = {
        "email": email,
        "password": password,
    }
    login_response = await client.post("/api/v1/auth/login", json=login_payload)
    assert login_response.status_code == 200
    login_data = login_response.json()
    assert "access_token" in login_data

    # 4. Refrescar token
    refresh_payload = {"refresh_token": refresh_token}
    refresh_response = await client.post("/api/v1/auth/refresh", json=refresh_payload)
    assert refresh_response.status_code == 200
    refreshed_data = refresh_response.json()
    assert "access_token" in refreshed_data


@pytest.mark.asyncio
async def test_login_invalid_password_returns_401(client: AsyncClient):
    """Verifica que un intento de inicio de sesión con contraseña errónea retorne 401."""
    login_payload = {
        "email": "non_existent@user.mx",
        "password": "wrong_password",
    }
    response = await client.post("/api/v1/auth/login", json=login_payload)
    assert response.status_code == 401
    data = response.json()
    assert data["success"] is False
    assert data["error"]["code"] == "AUTH_UNAUTHORIZED"


@pytest.mark.asyncio
async def test_protected_route_without_token_returns_401(client: AsyncClient):
    """Verifica que acceder a /auth/me sin Bearer token retorne 401."""
    response = await client.get("/api/v1/auth/me")
    assert response.status_code == 401
    data = response.json()
    assert data["success"] is False
    assert data["error"]["code"] == "AUTH_UNAUTHORIZED"
