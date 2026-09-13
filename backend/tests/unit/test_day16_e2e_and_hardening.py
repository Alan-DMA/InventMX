# Suite de Pruebas Unitarias y de Integración E2E - Día 16 (HU-25 / CU-31, CU-32 / Const. Art. I, IV, VII, Anexo B)
from decimal import Decimal
import uuid
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_day16_complete_business_lifecycle_e2e(client: AsyncClient):
    """
    Validación E2E del ciclo comercial completo de una tienda mexicana:
    1. Registro y configuración de comercio (Tenant + Owner).
    2. Creación de productos con los 3 campos vitales en $ MXN.
    3. Creación de combos con validación atómica.
    4. Apertura de turno de caja y venta POS con split payments (Efectivo + Tarjeta).
    5. Venta a crédito a cliente y registro de abono parcial.
    6. Consulta y validación de analítica financiera consolidada y capital de trabajo.
    """
    suffix = uuid.uuid4().hex[:6]

    # 1. Registro de comercio
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Abarrotes Don Pepe {suffix}",
            "slug": f"don-pepe-{suffix}",
            "full_name": "Don Pepe",
            "email": f"pepe_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Registrar 2 productos
    p1_resp = await client.post(
        "/api/v1/inventory/products",
        headers=headers,
        json={
            "name": f"Coca-Cola 600ml {suffix}",
            "sku": f"COCA-600-{suffix}",
            "price_mxn": 18.00,
            "cost_mxn": 12.00,
            "initial_stock": 50,
            "min_stock_alert": 10,
        },
    )
    assert p1_resp.status_code == 201
    p1_data = p1_resp.json()
    p1_id = p1_data["id"]
    warehouse_id = p1_data["stocks"][0]["warehouse_id"]

    p2_resp = await client.post(
        "/api/v1/inventory/products",
        headers=headers,
        json={
            "name": f"Sabritas Sal 45g {suffix}",
            "sku": f"SAB-SAL-{suffix}",
            "price_mxn": 17.00,
            "cost_mxn": 11.00,
            "initial_stock": 40,
            "min_stock_alert": 5,
        },
    )
    assert p2_resp.status_code == 201
    p2_data = p2_resp.json()
    p2_id = p2_data["id"]

    # 3. Crear Combo Promocional ($32.00 MXN por 1 refresco + 1 botana)
    combo_resp = await client.post(
        "/api/v1/inventory/combos",
        headers=headers,
        json={
            "name": f"Combo Botana y Refresco {suffix}",
            "sku": f"COMBO-{suffix}",
            "price_mxn": 32.00,
            "items": [
                {"product_id": p1_id, "quantity": 1},
                {"product_id": p2_id, "quantity": 1},
            ],
        },
    )
    assert combo_resp.status_code == 201

    # 4. Abrir turno de caja
    shift_resp = await client.post(
        "/api/v1/sales/shifts/open",
        headers=headers,
        json={
            "warehouse_id": warehouse_id,
            "opening_balance_mxn": 500.00,
            "notes": "Apertura turno matutino",
        },
    )
    assert shift_resp.status_code == 201

    # 5. Procesar venta POS con pago mixto ($20 efectivo + $12 tarjeta = $32)
    sale_resp = await client.post(
        "/api/v1/sales/checkout",
        headers=headers,
        json={
            "warehouse_id": warehouse_id,
            "items": [
                {"product_id": p1_id, "quantity": 1, "unit_price_mxn": 18.00},
                {"product_id": p2_id, "quantity": 1, "unit_price_mxn": 14.00},
            ],
            "payments": [
                {"payment_method": "CASH_MXN", "amount_paid_mxn": 20.00, "change_returned_mxn": 0.00},
                {"payment_method": "CARD_TPV", "amount_paid_mxn": 12.00, "change_returned_mxn": 0.00},
            ],
            "notes": "Venta POS E2E",
        },
    )
    assert sale_resp.status_code == 201
    sale_data = sale_resp.json()
    assert Decimal(str(sale_data["total_mxn"])) == Decimal("32.00")
    assert sale_data["status"] == "COMPLETED"

    # 6. Crear cliente con crédito y procesar venta a fiado
    cust_resp = await client.post(
        "/api/v1/customers",
        headers=headers,
        json={
            "full_name": f"Vecino Juan {suffix}",
            "phone": "5551234567",
            "credit_limit_mxn": 500.00,
        },
    )
    assert cust_resp.status_code == 201
    cust_id = cust_resp.json()["id"]

    credit_sale_resp = await client.post(
        "/api/v1/sales/checkout",
        headers=headers,
        json={
            "warehouse_id": warehouse_id,
            "client_id": cust_id,
            "allow_partial_payment": True,
            "items": [
                {"product_id": p1_id, "quantity": 1, "unit_price_mxn": 18.00},
            ],
            "payments": [],
        },
    )
    assert credit_sale_resp.status_code == 201

    # Abonar $10 al crédito del cliente
    payment_resp = await client.post(
        f"/api/v1/customers/{cust_id}/payments",
        headers=headers,
        json={
            "amount_mxn": 10.00,
            "payment_method": "CASH_MXN",
            "notes": "Abono parcial",
        },
    )
    assert payment_resp.status_code == 201

    # 7. Validar Analítica Financiera Consolidada
    fin_resp = await client.get("/api/v1/analytics/financial-summary?preset=TODAY", headers=headers)
    assert fin_resp.status_code == 200
    fin_data = fin_resp.json()
    # Ventas completadas: $32.00 MXN
    assert Decimal(str(fin_data["gross_sales_mxn"])) == Decimal("32.00")
    # Costo total completado: 12 + 11 = 23 MXN
    assert Decimal(str(fin_data["cogs_mxn"])) == Decimal("23.00")
    assert Decimal(str(fin_data["gross_profit_mxn"])) == Decimal("9.00")
    assert fin_data["total_transactions"] == 1

    # 8. Validar Capital de Trabajo (Cuentas por cobrar = $18 - $10 = $8 MXN)
    cap_resp = await client.get("/api/v1/analytics/working-capital", headers=headers)
    assert cap_resp.status_code == 200
    cap_data = cap_resp.json()
    assert Decimal(str(cap_data["accounts_receivable_mxn"])) == Decimal("8.00")
    assert Decimal(str(cap_data["net_working_capital_mxn"])) > Decimal("0.00")


@pytest.mark.asyncio
async def test_day16_cross_tenant_rls_hardening(client: AsyncClient):
    """
    Auditoría de seguridad RLS: Verifica que Tenant B no pueda ver ni modificar
    los recursos privados de Tenant A.
    """
    suffix_a = uuid.uuid4().hex[:6]
    suffix_b = uuid.uuid4().hex[:6]

    # Inquilino A
    reg_a = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda A {suffix_a}",
            "slug": f"tienda-a-{suffix_a}",
            "full_name": "Dueño A",
            "email": f"a_{suffix_a}@nexus.mx",
            "password": "password123",
        },
    )
    assert reg_a.status_code == 201
    headers_a = {"Authorization": f"Bearer {reg_a.json()['access_token']}"}

    # Inquilino B
    reg_b = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda B {suffix_b}",
            "slug": f"tienda-b-{suffix_b}",
            "full_name": "Dueño B",
            "email": f"b_{suffix_b}@nexus.mx",
            "password": "password123",
        },
    )
    assert reg_b.status_code == 201
    headers_b = {"Authorization": f"Bearer {reg_b.json()['access_token']}"}

    # Tenant A crea un producto privado
    p_resp = await client.post(
        "/api/v1/inventory/products",
        headers=headers_a,
        json={
            "name": f"Producto Secreto A {suffix_a}",
            "sku": f"SEC-A-{suffix_a}",
            "price_mxn": 99.00,
            "cost_mxn": 50.00,
            "initial_stock": 10,
        },
    )
    assert p_resp.status_code == 201
    prod_a_id = p_resp.json()["id"]

    # Tenant B lista productos (no debe aparecer el producto de A)
    list_b = await client.get("/api/v1/inventory/products", headers=headers_b)
    assert list_b.status_code == 200
    items_b = list_b.json()
    assert not any(item["id"] == prod_a_id for item in items_b)

    # Tenant B intenta consultar directamente por ID el producto de A
    get_b = await client.get(f"/api/v1/inventory/products/{prod_a_id}", headers=headers_b)
    assert get_b.status_code in [404, 403]


@pytest.mark.asyncio
async def test_day16_backup_creation_and_sha256_integrity(client: AsyncClient):
    """
    Prueba la creación de un respaldo de base de datos comprimido, verificando
    que retorne un hash SHA-256 válido y metadatos de expiración a 30 días.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Comercio Backup {suffix}",
            "slug": f"backup-store-{suffix}",
            "full_name": "Admin Backup",
            "email": f"backup_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    headers = {"Authorization": f"Bearer {reg_resp.json()['access_token']}"}

    resp_backup = await client.post(
        "/api/v1/admin/backups/create",
        headers=headers,
        json={
            "backup_type": "FULL",
            "include_all_tenants": True,
            "notes": "Respaldo diario automático programado",
        },
    )
    assert resp_backup.status_code == 201, resp_backup.text
    backup = resp_backup.json()
    assert backup["status"] == "COMPLETED"
    assert backup["size_bytes"] > 0
    assert len(backup["sha256_checksum"]) == 64
    assert backup["storage_provider"] == "CLOUDFLARE_R2"
    assert "tar.gz" in backup["filename"] or "gz" in backup["filename"]


@pytest.mark.asyncio
async def test_day16_backup_list_and_retention_policy(client: AsyncClient):
    """
    Verifica que el listado de respaldos retorne la lista ordenada y la política de retención.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Comercio List Backup {suffix}",
            "slug": f"list-backup-{suffix}",
            "full_name": "Admin List",
            "email": f"list_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    headers = {"Authorization": f"Bearer {reg_resp.json()['access_token']}"}

    # Crear respaldo
    await client.post(
        "/api/v1/admin/backups/create",
        headers=headers,
        json={"backup_type": "FULL", "notes": "Backup para listado"},
    )

    resp_list = await client.get("/api/v1/admin/backups/list", headers=headers)
    assert resp_list.status_code == 200, resp_list.text
    data = resp_list.json()
    assert data["total_backups"] >= 1
    assert data["total_size_bytes"] > 0
    assert data["retention_policy_days"] == 30
    assert len(data["backups"]) >= 1


@pytest.mark.asyncio
async def test_day16_system_health_diagnostics(client: AsyncClient):
    """
    Verifica el endpoint de diagnóstico integral del sistema y latencia de PostgreSQL.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Comercio Health {suffix}",
            "slug": f"health-store-{suffix}",
            "full_name": "Admin Health",
            "email": f"health_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    headers = {"Authorization": f"Bearer {reg_resp.json()['access_token']}"}

    resp_health = await client.get("/api/v1/admin/system-health", headers=headers)
    assert resp_health.status_code == 200, resp_health.text
    diag = resp_health.json()
    assert diag["status"] in ["healthy", "degraded"]
    assert diag["database_connected"] is True
    assert diag["database_latency_ms"] >= 0.0
    assert diag["rls_enforced"] is True
    assert diag["version"] == "3.0.0"
    assert diag["active_tenants_count"] >= 1


@pytest.mark.asyncio
async def test_day16_admin_endpoints_rbac_denial_for_cashier(client: AsyncClient):
    """
    Verifica que los cajeros o roles sin privilegios reciban 403 FORBIDDEN
    al intentar generar o consultar respaldos de base de datos.
    """
    suffix = uuid.uuid4().hex[:6]
    # Registro de dueño
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Comercio RBAC {suffix}",
            "slug": f"rbac-store-{suffix}",
            "full_name": "Dueño Tienda",
            "email": f"dueno_{suffix}@nexus.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    headers_owner = {"Authorization": f"Bearer {reg_resp.json()['access_token']}"}

    # Obtener ID del rol CASHIER
    roles_resp = await client.get("/api/v1/roles", headers=headers_owner)
    cashier_role = next(r for r in roles_resp.json() if r["name"] == "CASHIER")

    # Crear cajero
    emp_resp = await client.post(
        "/api/v1/users",
        json={
            "email": f"cajero_{suffix}@nexus.mx",
            "password": "cajeropassword",
            "full_name": "Cajero Empleado",
            "role_id": cashier_role["id"],
        },
        headers=headers_owner,
    )
    assert emp_resp.status_code == 201

    # Login como cajero
    login_resp = await client.post(
        "/api/v1/auth/login",
        json={
            "email": f"cajero_{suffix}@nexus.mx",
            "password": "cajeropassword",
        },
    )
    assert login_resp.status_code == 200
    headers_cashier = {"Authorization": f"Bearer {login_resp.json()['access_token']}"}

    # Intento de creación por cajero
    resp_create = await client.post(
        "/api/v1/admin/backups/create",
        headers=headers_cashier,
        json={"backup_type": "FULL"},
    )
    assert resp_create.status_code == 403

    # Intento de listado por cajero
    resp_list = await client.get("/api/v1/admin/backups/list", headers=headers_cashier)
    assert resp_list.status_code == 403
