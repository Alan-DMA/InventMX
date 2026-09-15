import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy import select, text
from decimal import Decimal
from uuid import UUID

from app.main import app
from app.core.config import settings
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.pool import NullPool
from app.core.security import get_password_hash, create_access_token
from app.models.models import (
    Tenant, User, Role, Product, Inventory, Warehouse, Permission, 
    role_permissions, Sale, SaleItem, SalePayment
)

pytestmark = pytest.mark.asyncio

@pytest.fixture(scope="module")
def anyio_backend():
    return "asyncio"

# Superuser connection to setup and teardown test data without RLS interference
superuser_url = settings.DATABASE_URL.replace("nexus_app", "postgres")
superuser_engine = create_async_engine(superuser_url, echo=False, poolclass=NullPool)
SuperuserSessionLocal = async_sessionmaker(
    bind=superuser_engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def setup_sales_test_data():
    """Inicializa datos para pruebas de ventas."""
    async with SuperuserSessionLocal() as session:
        await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
        
        plan_id = "00000000-0000-0000-0000-000000000002" # Plan Comercio
        
        # Tenants
        tenant_a = Tenant(
            id="a0000000-0000-0000-0000-0000000000aa",
            name="Comercio Venta A",
            plan_id=plan_id,
            current_exchange_rate=Decimal("40.0000") # Tasa de cambio de prueba
        )
        
        exist_t_res = await session.execute(select(Tenant).where(Tenant.id == tenant_a.id))
        exist_tenant = exist_t_res.scalars().first()
        if not exist_tenant:
            session.add(tenant_a)
        else:
            exist_tenant.current_exchange_rate = Decimal("40.0000")
        await session.commit()

        # Roles
        role_a = Role(id="d0000000-0000-0000-0000-0000000000aa", tenant_id=tenant_a.id, name="TENANT_OWNER")
        exist_r_res = await session.execute(select(Role).where(Role.id == role_a.id))
        exist_role = exist_r_res.scalars().first()
        if not exist_role:
            session.add(role_a)
        await session.commit()

        # Vincular permisos a rol
        perms_result = await session.execute(select(Permission))
        all_perms = perms_result.scalars().all()
        await session.execute(role_permissions.delete().where(role_permissions.c.role_id == role_a.id))
        
        all_associations = [{"role_id": role_a.id, "permission_id": p.id} for p in all_perms]
        if all_associations:
            await session.execute(role_permissions.insert(), all_associations)
            await session.commit()

        # Almacén Principal
        wh_a = Warehouse(id="f0000000-0000-0000-0000-0000000000aa", tenant_id=tenant_a.id, name="Almacén Principal")
        exist_w_res = await session.execute(select(Warehouse).where(Warehouse.id == wh_a.id))
        exist_wh = exist_w_res.scalars().first()
        if not exist_wh:
            session.add(wh_a)
        await session.commit()

        # Vendedor (Usuario con tasa de comisión del 10%)
        seller_a = User(
            id="e0000000-0000-0000-0000-0000000000aa",
            tenant_id=tenant_a.id,
            username="vendedor_a",
            email="vendedor_a@test.com",
            password_hash=get_password_hash("password123"),
            role_id=role_a.id,
            commission_rate=Decimal("10.00"),  # 10% de comisión sobre margen neto
            is_active=True
        )
        exist_u_res = await session.execute(select(User).where(User.id == seller_a.id))
        exist_user = exist_u_res.scalars().first()
        if not exist_user:
            session.add(seller_a)
        else:
            exist_user.commission_rate = Decimal("10.00")
        await session.commit()

        # Productos
        prod_1 = Product(
            id="c0000000-0000-0000-0000-000000000001",
            tenant_id=tenant_a.id,
            name="Harina de prueba",
            barcode="BarHarina1",
            cost_usd=Decimal("1.00"),  # Costo congelado
            price_usd=Decimal("2.00"),  # Precio de venta
            is_active=True
        )
        
        exist_p_res = await session.execute(select(Product).where(Product.id == prod_1.id))
        exist_prod = exist_p_res.scalars().first()
        if not exist_prod:
            session.add(prod_1)
        await session.commit()

        # Inicializar Inventario
        inv_1 = Inventory(
            tenant_id=tenant_a.id,
            product_id=prod_1.id,
            warehouse_id=wh_a.id,
            stock_available=Decimal("50.00"),
            stock_reserved=Decimal("0.00")
        )
        # Limpiar inventarios viejos del test
        await session.execute(text("DELETE FROM inventory WHERE tenant_id = 'a0000000-0000-0000-0000-0000000000aa'"))
        session.add(inv_1)
        await session.commit()

        return tenant_a.id, seller_a.id, prod_1.id, wh_a.id


async def clean_sales(tenant_id):
    """Limpia los registros de venta de prueba."""
    async with SuperuserSessionLocal() as session:
        await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
        await session.execute(text(f"DELETE FROM sale_payments WHERE tenant_id = '{tenant_id}'"))
        await session.execute(text(f"DELETE FROM sale_items WHERE tenant_id = '{tenant_id}'"))
        await session.execute(text(f"DELETE FROM sales WHERE tenant_id = '{tenant_id}'"))
        await session.execute(text(f"DELETE FROM inventory_movements WHERE tenant_id = '{tenant_id}'"))
        # Resetear stock
        await session.execute(text(f"UPDATE inventory SET stock_available = 50.00, stock_reserved = 0.00 WHERE tenant_id = '{tenant_id}'"))
        await session.commit()


async def test_full_sale_lifecycle_and_commissions():
    """Prueba el ciclo de vida completo de una venta, la reserva/salida de stock y comisiones del vendedor."""
    tenant_id, seller_id, prod_id, warehouse_id = await setup_sales_test_data()
    await clean_sales(tenant_id)

    token = create_access_token(subject=seller_id)
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        
        # 1. Crear una Venta en estado DRAFT de 2 Harinas (Costo 1$, Venta 2$)
        create_res = await ac.post(
            "/api/v1/sales",
            headers=headers,
            json={
                "seller_id": str(seller_id),
                "items": [
                    {
                        "product_id": str(prod_id),
                        "quantity": 2,
                        "unit_price_usd": 2.00
                    }
                ]
            }
        )
        assert create_res.status_code == 201
        sale_data = create_res.json()
        sale_id = sale_data["id"]
        
        assert sale_data["status"] == "DRAFT"
        assert float(sale_data["total_usd"]) == 4.00
        # Se congela la tasa de cambio del inquilino (40.00)
        assert float(sale_data["exchange_rate_applied"]) == 40.00

        # Verificar que el stock siga en disponible 50
        async with SuperuserSessionLocal() as session:
            await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
            inv = (await session.execute(select(Inventory).where(Inventory.product_id == prod_id))).scalars().first()
            assert inv.stock_available == Decimal("50.00")
            assert inv.stock_reserved == Decimal("0.00")

        # 2. Transicionar DRAFT -> PENDING_PAYMENT (Debe reservar 2 unidades en stock)
        trans_1 = await ac.post(
            f"/api/v1/sales/{sale_id}/transition",
            headers=headers,
            json={"new_status": "PENDING_PAYMENT"}
        )
        assert trans_1.status_code == 200
        assert trans_1.json()["status"] == "PENDING_PAYMENT"

        # Verificar stock reservado
        async with SuperuserSessionLocal() as session:
            await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
            inv = (await session.execute(select(Inventory).where(Inventory.product_id == prod_id))).scalars().first()
            assert inv.stock_available == Decimal("48.00")
            assert inv.stock_reserved == Decimal("2.00")

        # 3. Registrar Pago Mixto (total de la venta es 4 USD)
        # Pagamos 2 USD en efectivo y Bs. 80 en Pago Móvil (a tasa 40, equivale a 2 USD)
        pay_res = await ac.post(
            f"/api/v1/sales/{sale_id}/payments",
            headers=headers,
            json=[
                {"payment_method": "EFECTIVO_USD", "amount_usd": 2.00, "amount_ves": 0.00},
                {"payment_method": "PAGO_MOVIL", "amount_usd": 2.00, "amount_ves": 80.00, "reference_number": "ref1234"}
            ]
        )
        assert pay_res.status_code == 200
        assert len(pay_res.json()["payments"]) == 2

        # 4. Transicionar PENDING_PAYMENT -> PAID (Debe calcular comisiones)
        # Margen = (2 USD - 1 USD) * 2 = 2 USD
        # Comisión = 2 USD * 10% = 0.2 USD
        trans_2 = await ac.post(
            f"/api/v1/sales/{sale_id}/transition",
            headers=headers,
            json={"new_status": "PAID"}
        )
        assert trans_2.status_code == 200
        paid_data = trans_2.json()
        assert paid_data["status"] == "PAID"
        assert float(paid_data["commission_amount_usd"]) == 0.20

        # 5. Transicionar PAID -> COMPLETED (Consumir stock reservado: despachado)
        trans_3 = await ac.post(
            f"/api/v1/sales/{sale_id}/transition",
            headers=headers,
            json={"new_status": "COMPLETED"}
        )
        assert trans_3.status_code == 200
        assert trans_3.json()["status"] == "COMPLETED"

        # Verificar que stock reservado se consuma (queda en 0, disponible en 48)
        async with SuperuserSessionLocal() as session:
            await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
            inv = (await session.execute(select(Inventory).where(Inventory.product_id == prod_id))).scalars().first()
            assert inv.stock_available == Decimal("48.00")
            assert inv.stock_reserved == Decimal("0.00")


async def test_sale_refund_returns_inventory():
    """Valida que reembolsar una venta completada devuelva las existencias a disponible y anule comisiones."""
    tenant_id, seller_id, prod_id, warehouse_id = await setup_sales_test_data()
    await clean_sales(tenant_id)

    token = create_access_token(subject=seller_id)
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Crear venta
        create_res = await ac.post(
            "/api/v1/sales",
            headers=headers,
            json={
                "seller_id": str(seller_id),
                "items": [{"product_id": str(prod_id), "quantity": 5, "unit_price_usd": 2.00}]
            }
        )
        sale_id = create_res.json()["id"]

        # 2. Reservar stock
        await ac.post(f"/api/v1/sales/{sale_id}/transition", headers=headers, json={"new_status": "PENDING_PAYMENT"})

        # 3. Pagar
        await ac.post(
            f"/api/v1/sales/{sale_id}/payments",
            headers=headers,
            json=[{"payment_method": "EFECTIVO_USD", "amount_usd": 10.00, "amount_ves": 0.00}]
        )
        await ac.post(f"/api/v1/sales/{sale_id}/transition", headers=headers, json={"new_status": "PAID"})

        # 4. Completar despacho (Stock disponible queda en 45)
        await ac.post(f"/api/v1/sales/{sale_id}/transition", headers=headers, json={"new_status": "COMPLETED"})

        # 5. Reembolsar (REFUNDED)
        refund_res = await ac.post(
            f"/api/v1/sales/{sale_id}/transition",
            headers=headers,
            json={"new_status": "REFUNDED"}
        )
        assert refund_res.status_code == 200
        refund_data = refund_res.json()
        assert refund_data["status"] == "REFUNDED"
        # Comisión se anula a cero
        assert float(refund_data["commission_amount_usd"]) == 0.00

        # Verificar que el stock devuelto regrese a disponible (vuelve a 50)
        async with SuperuserSessionLocal() as session:
            await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
            inv = (await session.execute(select(Inventory).where(Inventory.product_id == prod_id))).scalars().first()
            assert inv.stock_available == Decimal("50.00")
            assert inv.stock_reserved == Decimal("0.00")
