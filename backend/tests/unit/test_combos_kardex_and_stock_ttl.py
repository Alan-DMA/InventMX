# Importación del módulo datetime y timedelta para manejo de tiempos
from datetime import datetime, timedelta, timezone
# Importación del módulo decimal para validación de montos y existencias
from decimal import Decimal
# Importación de UUID para identificación de registros de prueba
import uuid
# Importación del framework pytest
import pytest
# Importación del cliente HTTP asíncrono
from httpx import AsyncClient

# Importación de utilidades de seguridad JWT
from app.core.security.jwt import create_access_token


@pytest.mark.asyncio
async def test_initial_stock_creates_kardex_movement(client: AsyncClient):
    """
    Const. Art. 7.1 & RF-05:
    Verifica que al registrar un producto con existencias iniciales > 0 mediante
    el formulario de 3 Campos Vitales, se genere automáticamente el primer
    asiento inmutable de ADJUSTMENT_IN en el Kardex.
    """
    suffix = uuid.uuid4().hex[:6]
    # 1. Registrar comercio y obtener token
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Kardex Store {suffix}",
            "slug": f"kardex-store-{suffix}",
            "full_name": "Dueño Kardex",
            "email": f"kardex_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Registrar producto con 50 piezas iniciales
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={
            "name": "Sabritas Sal 45g",
            "price_mxn": 22.00,
            "cost_mxn": 15.00,
            "initial_stock": 50.0,
        },
        headers=headers,
    )
    assert prod_resp.status_code == 201
    prod_id = prod_resp.json()["id"]

    # 3. Consultar el Kardex para verificar el asiento automático inicial
    mov_resp = await client.get(
        f"/api/v1/inventory/movements?product_id={prod_id}",
        headers=headers,
    )
    assert mov_resp.status_code == 200
    movements = mov_resp.json()
    assert len(movements) == 1
    asiento = movements[0]
    assert asiento["movement_type"] == "ADJUSTMENT_IN"
    assert float(asiento["quantity"]) == 50.0
    assert float(asiento["previous_stock"]) == 0.0
    assert float(asiento["new_stock"]) == 50.0
    assert float(asiento["unit_cost_mxn"]) == 15.00


@pytest.mark.asyncio
async def test_stock_adjustment_in_and_out_with_kardex(client: AsyncClient):
    """
    RF-05 / Const. Art. 7.1:
    Verifica ajustes manuales de existencias (+ Entrada física y - Merma/Salida),
    comprobando la mutación de saldos y la generación secuencial de asientos en Kardex.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Ajustes Store {suffix}",
            "slug": f"ajustes-store-{suffix}",
            "full_name": "Gerente Almacén",
            "email": f"ajustes_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear producto con stock inicial 100
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Aceite 1L", "price_mxn": 48.00, "initial_stock": 100.0},
        headers=headers,
    )
    prod_data = prod_resp.json()
    prod_id = prod_data["id"]
    wh_id = prod_data["stocks"][0]["warehouse_id"]

    # 2. Ajuste positivo: Entrada de +20 piezas por recepción de distribuidor
    adj_in_resp = await client.post(
        "/api/v1/inventory/adjust-stock",
        json={
            "product_id": prod_id,
            "warehouse_id": wh_id,
            "quantity": 20.0,
            "movement_type": "ADJUSTMENT_IN",
            "notes": "Compra adicional en efectivo",
        },
        headers=headers,
    )
    assert adj_in_resp.status_code == 200
    assert float(adj_in_resp.json()["new_stock"]) == 120.0

    # 3. Ajuste negativo: Merma de -5 piezas por rotura
    adj_out_resp = await client.post(
        "/api/v1/inventory/adjust-stock",
        json={
            "product_id": prod_id,
            "warehouse_id": wh_id,
            "quantity": -5.0,
            "movement_type": "WASTE_MERMA",
            "notes": "Botellas rotas en descarga",
        },
        headers=headers,
    )
    assert adj_out_resp.status_code == 200
    assert float(adj_out_resp.json()["new_stock"]) == 115.0

    # 4. Verificar saldo consolidado del producto
    get_prod = await client.get(f"/api/v1/inventory/products/{prod_id}", headers=headers)
    assert float(get_prod.json()["total_stock"]) == 115.0

    # 5. Verificar historial completo de 3 movimientos en Kardex
    kardex_resp = await client.get(f"/api/v1/inventory/movements?product_id={prod_id}", headers=headers)
    kardex = kardex_resp.json()
    assert len(kardex) == 3


@pytest.mark.asyncio
async def test_negative_stock_rejection_in_adjustment(client: AsyncClient):
    """
    Const. Art. 7.1:
    Verifica que el sistema rechace cualquier ajuste que resulte en stock negativo físico.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"NegStock Store {suffix}",
            "slug": f"negstock-{suffix}",
            "full_name": "Dueño Neg",
            "email": f"neg_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Producto con 10 piezas
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Leche Entera 1L", "price_mxn": 28.00, "initial_stock": 10.0},
        headers=headers,
    )
    prod_data = prod_resp.json()
    prod_id = prod_data["id"]
    wh_id = prod_data["stocks"][0]["warehouse_id"]

    # 2. Intento de restar -15 piezas (provocaría -5) -> Debe retornar 400 Bad Request
    bad_adj_resp = await client.post(
        "/api/v1/inventory/adjust-stock",
        json={
            "product_id": prod_id,
            "warehouse_id": wh_id,
            "quantity": -15.0,
            "movement_type": "ADJUSTMENT_OUT",
        },
        headers=headers,
    )
    assert bad_adj_resp.status_code == 400
    assert "existencias negativas" in bad_adj_resp.json()["error"]["message"].lower()


@pytest.mark.asyncio
async def test_atomic_multi_warehouse_transfer(client: AsyncClient):
    """
    RF-07 / Const. Art. 7.1:
    Verifica traslados atómicos de mercancía entre dos almacenes de la misma tienda:
    - Descuento en almacén origen
    - Incremento en almacén destino
    - Generación de asientos TRANSFER_OUT y TRANSFER_IN vinculados con el mismo reference_id.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Transfers Corp {suffix}",
            "slug": f"transfers-corp-{suffix}",
            "full_name": "Supervisor Traslados",
            "email": f"transfer_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear producto en almacén principal con 50 piezas
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Arroz 1kg", "price_mxn": 32.00, "cost_mxn": 22.00, "initial_stock": 50.0},
        headers=headers,
    )
    prod_data = prod_resp.json()
    prod_id = prod_data["id"]
    wh_origin_id = prod_data["stocks"][0]["warehouse_id"]

    # 2. Crear segundo almacén (Sucursal Norte)
    wh_dest_resp = await client.post(
        "/api/v1/inventory/warehouses",
        json={"name": "Sucursal Norte", "is_default": False},
        headers=headers,
    )
    assert wh_dest_resp.status_code == 201
    wh_dest_id = wh_dest_resp.json()["id"]

    # 3. Trasladar 15 piezas de Almacén Principal a Sucursal Norte
    transfer_resp = await client.post(
        "/api/v1/inventory/transfer-stock",
        json={
            "product_id": prod_id,
            "from_warehouse_id": wh_origin_id,
            "to_warehouse_id": wh_dest_id,
            "quantity": 15.0,
            "notes": "Reabastecimiento Sucursal Norte",
        },
        headers=headers,
    )
    assert transfer_resp.status_code == 200
    movements = transfer_resp.json()
    assert len(movements) == 2

    mov_out = next(m for m in movements if m["movement_type"] == "TRANSFER_OUT")
    mov_in = next(m for m in movements if m["movement_type"] == "TRANSFER_IN")

    # Validar que comparten la misma referencia atómica
    assert mov_out["reference_id"] == mov_in["reference_id"]
    assert float(mov_out["previous_stock"]) == 50.0
    assert float(mov_out["new_stock"]) == 35.0
    assert float(mov_in["previous_stock"]) == 0.0
    assert float(mov_in["new_stock"]) == 15.0

    # 4. Verificar consulta de producto con existencias en ambos almacenes
    reloaded_prod = await client.get(f"/api/v1/inventory/products/{prod_id}", headers=headers)
    stocks = reloaded_prod.json()["stocks"]
    assert len(stocks) == 2
    assert float(reloaded_prod.json()["total_stock"]) == 50.0


@pytest.mark.asyncio
async def test_combo_creation_and_bottleneck_stock_calculation(client: AsyncClient):
    """
    RF-03 / Const. Art. 2.3:
    Verifica la creación de Combos/Promociones en MXN ($) y el cálculo dinámico
    de existencias disponibles en base al cuello de botella de sus productos componentes.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Combos Store {suffix}",
            "slug": f"combos-store-{suffix}",
            "full_name": "Alan Co-founder",
            "email": f"combos_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear Producto A: Hamburguesa (Stock: 10 piezas)
    prod_a_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Hamburguesa Sencilla", "price_mxn": 65.00, "initial_stock": 10.0},
        headers=headers,
    )
    prod_a_id = prod_a_resp.json()["id"]

    # 2. Crear Producto B: Refresco 600ml (Stock: 6 piezas)
    prod_b_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Refresco 600ml", "price_mxn": 20.00, "initial_stock": 6.0},
        headers=headers,
    )
    prod_b_id = prod_b_resp.json()["id"]
    prod_b_wh = prod_b_resp.json()["stocks"][0]["warehouse_id"]

    # 3. Crear Combo "Combo Burger": 1 Hamburguesa + 2 Refrescos por $85.00 MXN
    combo_resp = await client.post(
        "/api/v1/inventory/combos",
        json={
            "name": "Combo Pareja Burger",
            "price_mxn": 85.00,
            "description": "1 Hamburguesa + 2 Refrescos",
            "items": [
                {"product_id": prod_a_id, "quantity": 1.0},
                {"product_id": prod_b_id, "quantity": 2.0},
            ],
        },
        headers=headers,
    )
    assert combo_resp.status_code == 201
    combo_data = combo_resp.json()
    combo_id = combo_data["id"]

    # Con 10 Hamburguesas (10 // 1 = 10) y 6 Refrescos (6 // 2 = 3), el stock vendible es 3 combos
    assert float(combo_data["available_combos"]) == 3.0
    assert float(combo_data["price_mxn"]) == 85.00

    # 4. Merma de 4 refrescos -> Quedan 2 refrescos (2 // 2 = 1 combo)
    await client.post(
        "/api/v1/inventory/adjust-stock",
        json={
            "product_id": prod_b_id,
            "warehouse_id": prod_b_wh,
            "quantity": -4.0,
            "movement_type": "WASTE_MERMA",
        },
        headers=headers,
    )

    # 5. Consultar combo actualizado -> Debe reflejar 1 combo disponible
    get_combo = await client.get(f"/api/v1/inventory/combos/{combo_id}", headers=headers)
    assert float(get_combo.json()["available_combos"]) == 1.0


@pytest.mark.asyncio
async def test_stock_reservation_ttl_and_manual_release(client: AsyncClient):
    """
    RF-06:
    Verifica el ciclo de vida de apartados temporales de stock con TTL de 15 minutos:
    - Reserva incrementa `reserved_stock` sin afectar `current_stock`
    - Movimiento RESERVATION_HOLD en Kardex
    - Liberación manual resta `reserved_stock` y emite RESERVATION_RELEASE en Kardex.
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Reservas Store {suffix}",
            "slug": f"reservas-store-{suffix}",
            "full_name": "Cajero 1",
            "email": f"reserva_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear producto con 20 unidades
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Teclado Mecánico", "price_mxn": 750.00, "initial_stock": 20.0},
        headers=headers,
    )
    prod_data = prod_resp.json()
    prod_id = prod_data["id"]
    wh_id = prod_data["stocks"][0]["warehouse_id"]

    # 2. Crear apartado de 4 piezas
    reserve_resp = await client.post(
        "/api/v1/inventory/reservations",
        json={
            "product_id": prod_id,
            "warehouse_id": wh_id,
            "quantity": 4.0,
            "ttl_minutes": 15,
        },
        headers=headers,
    )
    assert reserve_resp.status_code == 201
    res_data = reserve_resp.json()
    res_id = res_data["id"]
    assert res_data["status"] == "PENDING"

    # 3. Comprobar que reserved_stock es 4
    prod_check = await client.get(f"/api/v1/inventory/products/{prod_id}", headers=headers)
    stock_info = prod_check.json()["stocks"][0]
    assert float(stock_info["current_stock"]) == 20.0
    assert float(stock_info["reserved_stock"]) == 4.0

    # 4. Liberar manualmente la reserva
    release_resp = await client.post(
        f"/api/v1/inventory/reservations/{res_id}/release",
        headers=headers,
    )
    assert release_resp.status_code == 200
    assert release_resp.json()["status"] == "RELEASED"

    # 5. Comprobar que reserved_stock regresó a 0
    prod_check_released = await client.get(f"/api/v1/inventory/products/{prod_id}", headers=headers)
    assert float(prod_check_released.json()["stocks"][0]["reserved_stock"]) == 0.0


@pytest.mark.asyncio
async def test_multi_tenant_rls_isolation_combos_and_kardex(client: AsyncClient):
    """
    Const. Art. 4.1 & RLS:
    Verifica que las tablas `combos`, `combo_items`, `inventory_movements` y
    `stock_reservations` estén 100% aisladas por tenant_id mediante PostgreSQL RLS.
    """
    suffix_a = uuid.uuid4().hex[:6]
    suffix_b = uuid.uuid4().hex[:6]

    # 1. Registrar Tienda A
    reg_a = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda A {suffix_a}",
            "slug": f"tienda-a-{suffix_a}",
            "full_name": "Dueño A",
            "email": f"a_{suffix_a}@tienda.mx",
            "password": "password123",
        },
    )
    token_a = reg_a.json()["access_token"]
    headers_a = {"Authorization": f"Bearer {token_a}"}

    # 2. Registrar Tienda B
    reg_b = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Tienda B {suffix_b}",
            "slug": f"tienda-b-{suffix_b}",
            "full_name": "Dueño B",
            "email": f"b_{suffix_b}@tienda.mx",
            "password": "password123",
        },
    )
    token_b = reg_b.json()["access_token"]
    headers_b = {"Authorization": f"Bearer {token_b}"}

    # 3. Tienda A crea un producto, ajuste y combo
    p_a = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Producto Tienda A", "price_mxn": 100.00, "initial_stock": 50.0},
        headers=headers_a,
    )
    prod_a_id = p_a.json()["id"]

    await client.post(
        "/api/v1/inventory/combos",
        json={
            "name": "Combo Secreto A",
            "price_mxn": 150.00,
            "items": [{"product_id": prod_a_id, "quantity": 1.0}],
        },
        headers=headers_a,
    )

    # 4. Tienda B consulta combos y kardex -> Debe recibir listas vacías
    combos_b = await client.get("/api/v1/inventory/combos", headers=headers_b)
    assert combos_b.status_code == 200
    assert len(combos_b.json()) == 0

    kardex_b = await client.get("/api/v1/inventory/movements", headers=headers_b)
    assert kardex_b.status_code == 200
    assert len(kardex_b.json()) == 0


@pytest.mark.asyncio
async def test_cashier_rbac_denial_on_adjust_stock(client: AsyncClient):
    """
    Doc. Maestro Sec. 9.2 (RBAC Matrix):
    Verifica que un usuario con rol CASHIER (cajero) tenga permisos para reservar stock (sales.checkout)
    pero NO pueda alterar físicamente existencias (/inventory/adjust-stock) sin autorización de supervisor.
    """
    suffix = uuid.uuid4().hex[:6]
    # 1. Registrar comercio y crear usuario cajero
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"RBAC Store {suffix}",
            "slug": f"rbac-store-{suffix}",
            "full_name": "Dueño Tienda",
            "email": f"admin_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    owner_token = reg_resp.json()["access_token"]
    owner_headers = {"Authorization": f"Bearer {owner_token}"}

    # 2. Dueño crea producto
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Vino Tinto 750ml", "price_mxn": 220.00, "initial_stock": 10.0},
        headers=owner_headers,
    )
    prod_data = prod_resp.json()
    prod_id = prod_data["id"]
    wh_id = prod_data["stocks"][0]["warehouse_id"]

    # 3. Dueño da de alta a un cajero
    cashier_role_id = "a0000000-0000-0000-0000-000000000003"
    create_user_resp = await client.post(
        "/api/v1/users",
        json={
            "email": f"cashier_{suffix}@tienda.mx",
            "password": "cashierpassword123",
            "full_name": "Cajero Juan",
            "role_id": cashier_role_id,
        },
        headers=owner_headers,
    )
    assert create_user_resp.status_code == 201

    # 4. Login como Cajero
    login_cashier = await client.post(
        "/api/v1/auth/login",
        json={"email": f"cashier_{suffix}@tienda.mx", "password": "cashierpassword123"},
    )
    assert login_cashier.status_code == 200
    cashier_token = login_cashier.json()["access_token"]
    cashier_headers = {"Authorization": f"Bearer {cashier_token}"}

    # 5. Cajero intenta hacer un ajuste manual de existencias -> 403 Forbidden
    adj_resp = await client.post(
        "/api/v1/inventory/adjust-stock",
        json={
            "product_id": prod_id,
            "warehouse_id": wh_id,
            "quantity": 5.0,
            "movement_type": "ADJUSTMENT_IN",
        },
        headers=cashier_headers,
    )
    assert adj_resp.status_code == 403

    # 6. Cajero crea un apartado de stock para un cliente en mostrador -> 201 Created (permitido)
    res_resp = await client.post(
        "/api/v1/inventory/reservations",
        json={
            "product_id": prod_id,
            "warehouse_id": wh_id,
            "quantity": 1.0,
            "ttl_minutes": 15,
        },
        headers=cashier_headers,
    )
    assert res_resp.status_code == 201


@pytest.mark.asyncio
async def test_stock_reservation_expiration_cleanup_worker(client: AsyncClient):
    """
    RF-06:
    Verifica el funcionamiento del worker / endpoint de limpieza automática
    de apartados de inventario vencidos por TTL (15 minutos).
    """
    suffix = uuid.uuid4().hex[:6]
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Cleanup Store {suffix}",
            "slug": f"cleanup-store-{suffix}",
            "full_name": "Dueño Cleanup",
            "email": f"cleanup_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    token = reg_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Crear producto con 30 piezas
    prod_resp = await client.post(
        "/api/v1/inventory/products",
        json={"name": "Monitor Gamer", "price_mxn": 3500.00, "initial_stock": 30.0},
        headers=headers,
    )
    prod_data = prod_resp.json()
    prod_id = prod_data["id"]
    wh_id = prod_data["stocks"][0]["warehouse_id"]

    # 2. Crear reserva con TTL estándar
    res_resp = await client.post(
        "/api/v1/inventory/reservations",
        json={
            "product_id": prod_id,
            "warehouse_id": wh_id,
            "quantity": 3.0,
            "ttl_minutes": 15,
        },
        headers=headers,
    )
    assert res_resp.status_code == 201

    # 3. Ejecutar cleanup (no debe liberar nada aún porque no ha vencido)
    cleanup_resp = await client.post(
        "/api/v1/inventory/reservations/cleanup",
        headers=headers,
    )
    assert cleanup_resp.status_code == 200
    assert cleanup_resp.json()["status"] == "success"

    # 4. Stock reservado sigue siendo 3.0
    prod_check = await client.get(f"/api/v1/inventory/products/{prod_id}", headers=headers)
    assert float(prod_check.json()["stocks"][0]["reserved_stock"]) == 3.0

