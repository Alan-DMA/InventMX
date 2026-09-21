# Importación de precisión decimal
from decimal import Decimal
# Importación de fecha y hora
from datetime import datetime, timezone
import uuid

# Importación de pytest y httpx
import pytest
from httpx import AsyncClient


async def create_store_and_get_auth(client: AsyncClient):
    """Registra una tienda y cajero/dueño y retorna (headers, tenant_id, user_id)."""
    suffix = uuid.uuid4().hex[:6]
    resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda Caja {suffix}",
            "slug": f"caja-store-{suffix}",
            "full_name": f"Cajero {suffix}",
            "email": f"caja_{suffix}@nexus.mx",
            "password": "Password123!",
        },
    )
    assert resp.status_code == 201
    data = resp.json()
    token = data["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return headers, data["user"]["tenant_id"], data["user"]["id"]


@pytest.mark.asyncio
async def test_cash_session_lifecycle_with_banxico_denominations(client: AsyncClient):
    """
    Verifica el flujo integral de caja:
    1. Apertura con desglose físico Banxico (POST /cash/open-session)
    2. Registro de retiro manual de efectivo (POST /cash/sessions/{id}/movements)
    3. Consulta de sesión activa (GET /cash/active-session)
    4. Cierre formal con arqueo ciego Banxico y clasificación de balance (POST /cash/close-session)
    5. Generación de reporte Corte Z (GET /cash/sessions/{id}/report)
    """
    headers, _, _ = await create_store_and_get_auth(client)

    # 1. Apertura con $500 MXN en denominaciones oficiales
    open_payload = {
        "opening_amount_mxn": 500.00,
        "opening_denominations": {
            "bills_500": 1,
            "bills_100": 0,
            "bills_50": 0,
            "bills_20": 0,
            "coins_20": 0,
            "coins_10": 0,
            "coins_5": 0,
            "coins_2": 0,
            "coins_1": 0,
            "coins_050": 0,
        },
        "notes": "Apertura de turno matutino con fondo inicial",
    }
    open_resp = await client.post(
        "/api/v1/cash/open-session",
        json=open_payload,
        headers=headers,
    )
    assert open_resp.status_code == 201
    session_data = open_resp.json()
    session_id = session_data["id"]
    assert session_data["status"] == "OPEN"
    assert float(session_data["opening_amount_mxn"]) == 500.00

    # 2. Intento de abrir una segunda sesión sin cerrar la anterior -> Rechazo 422
    dup_resp = await client.post(
        "/api/v1/cash/open-session",
        json=open_payload,
        headers=headers,
    )
    assert dup_resp.status_code == 422

    # 3. Consultar sesión activa
    active_resp = await client.get(
        "/api/v1/cash/active-session",
        headers=headers,
    )
    assert active_resp.status_code == 200
    assert active_resp.json()["id"] == session_id

    # 4. Registrar un retiro de $50 MXN (compra de insumos/bolsas)
    movement_payload = {
        "type": "WITHDRAWAL",
        "amount_mxn": 50.00,
        "description": "Compra de bolsas plásticas",
    }
    mov_resp = await client.post(
        f"/api/v1/cash/sessions/{session_id}/movements",
        json=movement_payload,
        headers=headers,
    )
    assert mov_resp.status_code == 201
    assert float(mov_resp.json()["amount_mxn"]) == 50.00

    # 5. Cierre de turno con arqueo físico:
    # Saldo teórico: 500 inicial - 50 retiro = 450 MXN.
    # El cajero cuenta: 2 billetes de $200 y 1 de $50 = $450 MXN (Cuadre exacto EXACT).
    close_payload = {
        "physical_denominations": {
            "bills_1000": 0,
            "bills_500": 0,
            "bills_200": 2,
            "bills_100": 0,
            "bills_50": 1,
            "bills_20": 0,
            "coins_20": 0,
            "coins_10": 0,
            "coins_5": 0,
            "coins_2": 0,
            "coins_1": 0,
            "coins_050": 0,
        },
        "notes": "Arqueo de cierre cuadrado al centavo",
    }
    close_resp = await client.post(
        "/api/v1/cash/close-session",
        json=close_payload,
        headers=headers,
    )
    assert close_resp.status_code == 200
    close_data = close_resp.json()
    assert close_data["session"]["status"] == "CLOSED"
    assert close_data["balance_summary"]["balance_result"] == "EXACT"
    assert float(close_data["balance_summary"]["difference_mxn"]) == 0.00

    # 6. Generar reporte de corte Z
    report_resp = await client.get(
        f"/api/v1/cash/sessions/{session_id}/report",
        headers=headers,
    )
    assert report_resp.status_code == 200
    report_data = report_resp.json()
    assert report_data["session_id"] == session_id
    assert "cash_balance" in report_data
    assert "denominations_breakdown" in report_data


@pytest.mark.asyncio
async def test_analytics_commissions_endpoint(client: AsyncClient):
    """
    Verifica que el endpoint canónico /api/v1/analytics/commissions
    retorne el tablero personal (resumen, desglose diario e histórico) del
    usuario en sesión. Desde Sep 21 no expone ranking ni comisiones ajenas:
    son dato privado de cada vendedor (decisión de Eduardo en QA).
    """
    headers, _, _ = await create_store_and_get_auth(client)
    response = await client.get(
        "/api/v1/analytics/commissions",
        headers=headers,
    )
    assert response.status_code == 200
    data = response.json()
    assert "period" in data
    assert "current_user" in data
    assert "summary" in data
    assert "daily_breakdown" in data
    assert len(data["history"]) == 6
    assert "ranking" not in data
    assert "cashiers" not in data
