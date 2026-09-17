import pytest
from httpx import AsyncClient


from app.core.config.settings import settings


@pytest.mark.asyncio
async def test_health_check_endpoint(client: AsyncClient):
    """
    Verifica que el endpoint /health responda 200 OK con estado online
    y base de datos conectada.
    """
    response = await client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "online"
    assert data["service"] == settings.PROJECT_NAME
    assert data["database"] == "connected"
