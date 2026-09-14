import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy import select, text
from decimal import Decimal
import io

from app.main import app
from app.core.database import AsyncSessionLocal
from app.core.config import settings
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from app.core.security import get_password_hash, create_access_token
from app.models.models import Tenant, User, Role, Product, Inventory, Warehouse, Permission, role_permissions

from sqlalchemy.pool import NullPool

# Crear un motor superusuario (postgres) para setup y cleanup de pruebas (bypass RLS)
superuser_url = settings.DATABASE_URL.replace("nexus_app", "postgres")
superuser_engine = create_async_engine(superuser_url, echo=False, poolclass=NullPool)
SuperuserSessionLocal = async_sessionmaker(
    bind=superuser_engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

# Marcamos las pruebas como asíncronas para pytest-asyncio
pytestmark = pytest.mark.asyncio

@pytest.fixture(scope="module")
def anyio_backend():
    return "asyncio"


async def setup_test_data():
    """Carga datos de prueba aislados en la base de datos."""
    async with SuperuserSessionLocal() as session:
        # 1. Limpiar RLS para poder poblar tablas globales
        await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
        
        # Obtener o crear un plan de prueba
        plan_id = "00000000-0000-0000-0000-000000000002" # Comercio
        
        # 2. Crear dos tenants de prueba
        tenant_a = Tenant(
            id="a0000000-0000-0000-0000-00000000000a",
            name="Comercio A",
            plan_id=plan_id
        )
        tenant_b = Tenant(
            id="b0000000-0000-0000-0000-00000000000b",
            name="Comercio B",
            plan_id=plan_id
        )
        
        # Evitar duplicados si ya existen de corridas anteriores
        for t in [tenant_a, tenant_b]:
            exist = await session.execute(select(Tenant).where(Tenant.id == t.id))
            if not exist.scalars().first():
                session.add(t)
        await session.commit()

        # 3. Crear roles OWNER para ambos tenants
        role_a = Role(id="d0000000-0000-0000-0000-00000000000a", tenant_id=tenant_a.id, name="TENANT_OWNER")
        role_b = Role(id="d0000000-0000-0000-0000-00000000000b", tenant_id=tenant_b.id, name="TENANT_OWNER")
        
        for r in [role_a, role_b]:
            exist = await session.execute(select(Role).where(Role.id == r.id))
            if not exist.scalars().first():
                session.add(r)
        await session.commit()

        # Asignar todos los permisos de inventario al rol OWNER (para pasar validación de deps)
        perms_result = await session.execute(select(Permission))
        all_perms = perms_result.scalars().all()
        
        # Limpiar asociaciones viejas de test
        await session.execute(role_permissions.delete().where(role_permissions.c.role_id.in_([role_a.id, role_b.id])))
        
        all_associations = []
        for r_id in [role_a.id, role_b.id]:
            all_associations.extend([{"role_id": r_id, "permission_id": p.id} for p in all_perms])
        if all_associations:
            await session.execute(role_permissions.insert(), all_associations)
            await session.commit()

        # 4. Crear almacenes principales
        wh_a = Warehouse(id="f0000000-0000-0000-0000-00000000000a", tenant_id=tenant_a.id, name="Almacén Principal")
        wh_b = Warehouse(id="f0000000-0000-0000-0000-00000000000b", tenant_id=tenant_b.id, name="Almacén Principal")
        for wh in [wh_a, wh_b]:
            exist = await session.execute(select(Warehouse).where(Warehouse.id == wh.id))
            if not exist.scalars().first():
                session.add(wh)
        await session.commit()

        # 5. Crear usuarios administradores
        user_a = User(
            id="e0000000-0000-0000-0000-00000000000a",
            tenant_id=tenant_a.id,
            username="admin_a",
            email="admin_a@test.com",
            password_hash=get_password_hash("password123"),
            role_id=role_a.id,
            is_active=True
        )
        user_b = User(
            id="e0000000-0000-0000-0000-00000000000b",
            tenant_id=tenant_b.id,
            username="admin_b",
            email="admin_b@test.com",
            password_hash=get_password_hash("password123"),
            role_id=role_b.id,
            is_active=True
        )
        for u in [user_a, user_b]:
            exist = await session.execute(select(User).where(User.id == u.id))
            if not exist.scalars().first():
                session.add(u)
        await session.commit()

        return tenant_a.id, user_a.id, tenant_b.id, user_b.id


async def clean_products(tenant_a_id, tenant_b_id):
    """Limpia los productos de prueba creados."""
    async with SuperuserSessionLocal() as session:
        await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
        await session.execute(text("DELETE FROM inventory_movements WHERE tenant_id IN ('a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b')"))
        await session.execute(text("DELETE FROM inventory WHERE tenant_id IN ('a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b')"))
        await session.execute(text("DELETE FROM products WHERE tenant_id IN ('a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b')"))
        await session.commit()


async def test_create_product_initializes_stock():
    """Valida que crear un producto por API inicializa existencias en el Almacén Principal."""
    tenant_a_id, user_a_id, _, _ = await setup_test_data()
    await clean_products(tenant_a_id, None)

    token = create_access_token(subject=user_a_id)
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Enviar petición para crear producto
        response = await ac.post(
            "/api/v1/inventory/products",
            headers=headers,
            json={
                "name": "Harina de Trigo Robin Hood",
                "barcode": "RobinHoodTest123",
                "cost_usd": 1.10,
                "price_usd": 1.50,
                "stock_inicial": 25.00
            }
        )
        assert response.status_code == 201
        data = response.json()
        product_id = data["id"]

        # Validar en base de datos que el inventario se haya creado con stock 25
        async with SuperuserSessionLocal() as session:
            await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
            inv_query = select(Inventory).where(Inventory.product_id == product_id)
            inv_result = await session.execute(inv_query)
            inventory = inv_result.scalars().first()
            
            assert inventory is not None
            assert inventory.stock_available == Decimal("25.0000")


async def test_rls_isolation():
    """Valida que el Tenant A no pueda ver ni listar los productos del Tenant B."""
    tenant_a_id, user_a_id, tenant_b_id, user_b_id = await setup_test_data()
    await clean_products(tenant_a_id, tenant_b_id)

    # 1. Crear un producto para el Tenant A
    async with SuperuserSessionLocal() as session:
        await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
        prod_a = Product(
            tenant_id=tenant_a_id,
            name="Producto exclusivo de Tenant A",
            barcode="BarTenantA",
            cost_usd=1.0,
            price_usd=2.0
        )
        prod_b = Product(
            tenant_id=tenant_b_id,
            name="Producto exclusivo de Tenant B",
            barcode="BarTenantB",
            cost_usd=10.0,
            price_usd=20.0
        )
        session.add_all([prod_a, prod_b])
        await session.commit()

    # 2. Consultar como Tenant A
    token_a = create_access_token(subject=user_a_id)
    headers_a = {"Authorization": f"Bearer {token_a}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.get("/api/v1/inventory/products", headers=headers_a)
        assert response.status_code == 200
        products_list = response.json()
        
        # Debemos ver el de A pero NO el de B
        names = [p["name"] for p in products_list]
        assert "Producto exclusivo de Tenant A" in names
        assert "Producto exclusivo de Tenant B" not in names


async def test_reserve_and_release_stock():
    """Valida los flujos de reserva y liberación de stock en el inventario."""
    tenant_a_id, user_a_id, _, _ = await setup_test_data()
    await clean_products(tenant_a_id, None)

    # 1. Crear producto con stock inicial 10
    token = create_access_token(subject=user_a_id)
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        prod_response = await ac.post(
            "/api/v1/inventory/products",
            headers=headers,
            json={
                "name": "Aceite Coposa",
                "barcode": "CoposaTest1",
                "cost_usd": 2.00,
                "price_usd": 3.00,
                "stock_inicial": 10.00
            }
        )
        product_id = prod_response.json()["id"]
        
        # Obtener warehouse ID
        async with SuperuserSessionLocal() as session:
            await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
            wh_query = select(Warehouse).where(Warehouse.tenant_id == tenant_a_id)
            wh = (await session.execute(wh_query)).scalars().first()
            warehouse_id = str(wh.id)

        # 2. Reservar 4 unidades
        reserve_res = await ac.post(
            "/api/v1/inventory/reserve",
            headers=headers,
            json={
                "product_id": product_id,
                "warehouse_id": warehouse_id,
                "quantity": 4.00,
                "sale_id": "sale-12345"
            }
        )
        assert reserve_res.status_code == 200
        data = reserve_res.json()
        assert float(data["stock_available"]) == 6.00
        assert float(data["stock_reserved"]) == 4.00

        # 3. Liberar 4 unidades
        release_res = await ac.post(
            "/api/v1/inventory/release",
            headers=headers,
            json={
                "product_id": product_id,
                "warehouse_id": warehouse_id,
                "quantity": 4.00,
                "sale_id": "sale-12345"
            }
        )
        assert release_res.status_code == 200
        data_release = release_res.json()
        assert float(data_release["stock_available"]) == 10.00
        assert float(data_release["stock_reserved"]) == 0.00


async def test_csv_upload_inventory():
    """Valida que la carga masiva mediante CSV inserte los productos e inicialice su Kardex."""
    tenant_a_id, user_a_id, _, _ = await setup_test_data()
    await clean_products(tenant_a_id, None)

    token = create_access_token(subject=user_a_id)
    headers = {"Authorization": f"Bearer {token}"}

    # Simular contenido de un archivo CSV
    csv_content = (
        "nombre,codigo_barras,costo_usd,precio_usd,precio_ves_manual,stock_inicial\n"
        "Pasta Primor 1kg,7590001,0.80,1.20,,100\n"
        "Azucar Montalban 1kg,7590002,1.00,1.50,55.00,50\n"
    )
    
    files = {
        "file": ("inventario.csv", io.BytesIO(csv_content.encode("utf-8")), "text/csv")
    }

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.post(
            "/api/v1/inventory/upload",
            headers=headers,
            files=files
        )
        assert response.status_code == 201
        assert response.json() == {"created": 2, "skipped": 0}

        # Verificar que se listen correctamente
        get_res = await ac.get("/api/v1/inventory/products", headers=headers)
        assert get_res.status_code == 200
        products = get_res.json()
        names = [p["name"] for p in products]
        assert "Pasta Primor 1kg" in names
        assert "Azucar Montalban 1kg" in names
