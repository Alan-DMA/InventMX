import asyncio
import uuid
import os
from datetime import datetime, timedelta
from decimal import Decimal
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from app.core.config import settings
from app.core.security import get_password_hash
from app.models.models import (
    Plan, Tenant, Permission, Role, User, Category, Product, 
    Warehouse, Inventory, InventoryMovement, Supplier, AccountsPayable,
    role_permissions
)

# M-06: Guardia de entorno — impide ejecución accidental en producción
if os.getenv("ENVIRONMENT", "development") == "production":
    raise RuntimeError(
        "FATAL: seed.py NO puede ejecutarse en un entorno de producción. "
        "Establece ENVIRONMENT=development para continuar."
    )

# Usar URL de superusuario (puede bypassear RLS)
su_url = settings.SUPERUSER_DATABASE_URL
su_engine = create_async_engine(su_url, echo=False)
SuSessionLocal = async_sessionmaker(su_engine, expire_on_commit=False)

async def seed_data():
    async with SuSessionLocal() as session:
        try:
            print("Iniciando la siembra de datos...")
            
            # Limpiar datos anteriores para permitir re-ejecución limpia
            await session.execute(text("TRUNCATE TABLE plans, permissions, tenants, roles, users, categories, products, warehouses, inventory, inventory_movements, suppliers, accounts_payable CASCADE;"))
            await session.commit()
            print("Tablas limpiadas para re-ejecución.")
            
            # --- 1. Crear Planes ---
            plan_emprendedor = Plan(
                id=uuid.UUID("00000000-0000-0000-0000-000000000001"),
                name="Emprendedor",
                price=Decimal("10.00"),
                max_users=2,
                max_warehouses=1
            )
            plan_comercio = Plan(
                id=uuid.UUID("00000000-0000-0000-0000-000000000002"),
                name="Comercio",
                price=Decimal("20.00"),
                max_users=5,
                max_warehouses=3
            )
            plan_corporativo = Plan(
                id=uuid.UUID("00000000-0000-0000-0000-000000000003"),
                name="Corporativo",
                price=Decimal("35.00"),
                max_users=15,
                max_warehouses=10
            )
            
            session.add_all([plan_emprendedor, plan_comercio, plan_corporativo])
            await session.commit()
            print("Planes creados.")

            # --- 2. Crear Permisos Globales ---
            permissions_list = [
                # Inventario
                Permission(name="inventario.ver", description="Ver productos y existencias de almacén"),
                Permission(name="inventario.crear", description="Crear nuevos productos"),
                Permission(name="inventario.editar", description="Editar información general de productos"),
                Permission(name="inventario.editar_precios", description="Modificar costos y precios en USD/VES de productos"),
                Permission(name="inventario.eliminar", description="Desactivar/eliminar productos"),
                # Ventas
                Permission(name="ventas.ver", description="Ver reportes e historial de ventas"),
                Permission(name="ventas.crear", description="Iniciar nuevas cotizaciones/ventas en borrador"),
                Permission(name="ventas.cobrar", description="Registrar cobros y completar ventas (descuenta stock)"),
                Permission(name="ventas.ver_costos", description="Visualizar ganancias netas y costos de compra en ventas"),
                Permission(name="ventas.eliminar", description="Anular/reembolsar ventas"),
                # Compras
                Permission(name="compras.ver", description="Ver órdenes de compra e historial de proveedores"),
                Permission(name="compras.crear", description="Registrar entradas de mercancía por órdenes de compra"),
                Permission(name="compras.eliminar", description="Anular compras registradas"),
                # Caja
                Permission(name="caja.ver", description="Ver estado de caja y reportes de cierres"),
                Permission(name="caja.arquear", description="Realizar aperturas, arqueos y cierres de caja multimoneda"),
                Permission(name="caja.movimientos", description="Registrar entradas/salidas manuales de dinero de caja"),
                # Usuarios y Roles
                Permission(name="usuarios.ver", description="Ver lista de usuarios y roles del comercio"),
                Permission(name="usuarios.gestionar", description="Crear, editar y dar de baja usuarios del comercio"),
                # Configuración de Suscripción SaaS (Sólamente Alan y Eduardo)
                Permission(name="saas.manage", description="Aprobación de pagos de suscripción del panel de fundadores")
            ]
            
            for perm in permissions_list:
                session.add(perm)
            await session.commit()
            print("Permisos globales creados.")

            tenant_sol = Tenant(
                id=uuid.UUID("a1a2a3a4-b1b2-c1c2-d1d2-000000000001"),
                name="Bodega El Sol",
                preferred_payment_method="PAGO_MOVIL",
                payment_instructions="Pago Móvil Banesco (0412-1234567, RIF: V-12345678-9)",
                plan_id=plan_comercio.id,
                subscription_status="ACTIVE",
                code="150467"
            )
            session.add(tenant_sol)
            await session.commit()
            print("Tenant 'Bodega El Sol' creado.")

            # CONFIGURAR CONTEXTO DE TENANT PARA EVITAR RLS EN ESTA SESIÓN
            # Las tablas creadas a continuación tienen tenant_id y se requiere RLS
            await session.execute(text("SELECT set_config('app.current_tenant', :tenant_id, false)"), {"tenant_id": str(tenant_sol.id)})

            # --- 4. Crear Roles para el Tenant ---
            role_owner = Role(
                id=uuid.UUID("d1a2a3a4-b1b2-c1c2-d1d2-000000000001"),
                tenant_id=tenant_sol.id,
                name="TENANT_OWNER",
                description="Propietario del comercio con acceso total"
            )
            role_manager = Role(
                id=uuid.UUID("d1a2a3a4-b1b2-c1c2-d1d2-000000000002"),
                tenant_id=tenant_sol.id,
                name="MANAGER",
                description="Administrador del comercio, gestiona stock y personal"
            )
            role_cashier = Role(
                id=uuid.UUID("d1a2a3a4-b1b2-c1c2-d1d2-000000000003"),
                tenant_id=tenant_sol.id,
                name="CASHIER",
                description="Cajero encargado del checkout rápido y arqueo"
            )
            role_salesperson = Role(
                id=uuid.UUID("d1a2a3a4-b1b2-c1c2-d1d2-000000000004"),
                tenant_id=tenant_sol.id,
                name="SALESPERSON",
                description="Vendedor enfocado en registro rápido de ventas"
            )
            
            session.add_all([role_owner, role_manager, role_cashier, role_salesperson])
            await session.commit()
            print("Roles creados para 'Bodega El Sol'.")

            # Asignar Permisos a los Roles insertando directamente en la tabla de asociación
            # OWNER tiene todo
            owner_perms = [{"role_id": role_owner.id, "permission_id": p.id} for p in permissions_list]
            
            # MANAGER tiene todo menos gestión de SaaS
            manager_perms = [{"role_id": role_manager.id, "permission_id": p.id} for p in permissions_list if p.name != "saas.manage"]
            
            # CASHIER
            cashier_perm_names = ["inventario.ver", "ventas.ver", "ventas.crear", "ventas.cobrar", "caja.ver", "caja.arquear", "caja.movimientos"]
            cashier_perms = [{"role_id": role_cashier.id, "permission_id": p.id} for p in permissions_list if p.name in cashier_perm_names]
            
            # SALESPERSON
            sales_perm_names = ["inventario.ver", "ventas.crear"]
            sales_perms = [{"role_id": role_salesperson.id, "permission_id": p.id} for p in permissions_list if p.name in sales_perm_names]
            
            all_association_entries = owner_perms + manager_perms + cashier_perms + sales_perms
            
            await session.execute(role_permissions.insert(), all_association_entries)
            await session.commit()
            print("Permisos asignados a los roles.")

            # --- 5. Crear Usuarios ---
            user_owner = User(
                id=uuid.UUID("e1a2a3a4-b1b2-c1c2-d1d2-000000000001"),
                tenant_id=tenant_sol.id,
                username="alandavidma",
                email="alandavidma@gmail.com",
                password_hash=get_password_hash("Ab123456"), # Encriptar contraseña
                role_id=role_owner.id,
                is_active=True,
            )
            user_cashier = User(
                id=uuid.UUID("e1a2a3a4-b1b2-c1c2-d1d2-000000000002"),
                tenant_id=tenant_sol.id,
                username="eduardo",
                email="eduardo@nexus.com",
                password_hash=get_password_hash("Cajero123"),
                role_id=role_cashier.id,
                is_active=True
            )
            
            session.add_all([user_owner, user_cashier])
            await session.commit()
            print("Usuarios de prueba creados.")

            # --- 6. Crear Almacenes ---
            warehouse_principal = Warehouse(
                id=uuid.UUID("f1a2a3a4-b1b2-c1c2-d1d2-000000000001"),
                tenant_id=tenant_sol.id,
                name="Almacén Principal",
                is_active=True
            )
            session.add(warehouse_principal)
            await session.commit()
            print("Almacén principal creado.")

            # --- 7. Crear Categorías ---
            cat_viveres = Category(
                id=uuid.UUID("c1a2a3a4-b1b2-c1c2-d1d2-000000000001"),
                tenant_id=tenant_sol.id,
                name="Víveres",
                description="Alimentos no perecederos y despensa"
            )
            cat_bebidas = Category(
                id=uuid.UUID("c1a2a3a4-b1b2-c1c2-d1d2-000000000002"),
                tenant_id=tenant_sol.id,
                name="Bebidas",
                description="Refrescos, jugos y agua mineral"
            )
            session.add_all([cat_viveres, cat_bebidas])
            await session.commit()
            print("Categorías creadas.")

            # --- 8. Crear Productos ---
            prod_harina = Product(
                id=uuid.UUID("b1a2a3a4-b1b2-c1c2-d1d2-000000000001"),
                tenant_id=tenant_sol.id,
                category_id=cat_viveres.id,
                barcode="7591007000108",
                name="Harina PAN 1kg",
                description="Harina de maíz blanco precocida",
                cost_usd=Decimal("1.00"),
                price_usd=Decimal("1.30"),
                is_active=True
            )
            prod_arroz = Product(
                id=uuid.UUID("b1a2a3a4-b1b2-c1c2-d1d2-000000000002"),
                tenant_id=tenant_sol.id,
                category_id=cat_viveres.id,
                barcode="7591007000153",
                name="Arroz Primor 1kg",
                description="Arroz blanco tipo I de grano entero",
                cost_usd=Decimal("0.90"),
                price_usd=Decimal("1.20"),
                is_active=True
            )
            prod_refresco = Product(
                id=uuid.UUID("b1a2a3a4-b1b2-c1c2-d1d2-000000000003"),
                tenant_id=tenant_sol.id,
                category_id=cat_bebidas.id,
                barcode="7590006000054",
                name="Coca-Cola 2L",
                description="Refresco sabor original botella retornable",
                cost_usd=Decimal("1.50"),
                price_usd=Decimal("2.00"),
                is_active=True
            )
            
            session.add_all([prod_harina, prod_arroz, prod_refresco])
            await session.commit()
            print("Productos creados.")

            # --- 9. Inicializar Stock de Inventario ---
            inv_harina = Inventory(
                tenant_id=tenant_sol.id,
                product_id=prod_harina.id,
                warehouse_id=warehouse_principal.id,
                stock_available=Decimal("25.00"),
                stock_reserved=Decimal("0.00")
            )
            inv_arroz = Inventory(
                tenant_id=tenant_sol.id,
                product_id=prod_arroz.id,
                warehouse_id=warehouse_principal.id,
                stock_available=Decimal("15.00"),
                stock_reserved=Decimal("0.00")
            )
            inv_refresco = Inventory(
                tenant_id=tenant_sol.id,
                product_id=prod_refresco.id,
                warehouse_id=warehouse_principal.id,
                stock_available=Decimal("30.00"),
                stock_reserved=Decimal("0.00")
            )
            session.add_all([inv_harina, inv_arroz, inv_refresco])
            await session.commit()
            print("Inventario de productos inicializado.")

            # --- 10. Registrar Movimientos de Inventario (Kardex) ---
            move_harina = InventoryMovement(
                tenant_id=tenant_sol.id,
                product_id=prod_harina.id,
                warehouse_id=warehouse_principal.id,
                quantity=Decimal("25.00"),
                type="ENTRADA",
                notes="Carga inicial de inventario de prueba"
            )
            move_arroz = InventoryMovement(
                tenant_id=tenant_sol.id,
                product_id=prod_arroz.id,
                warehouse_id=warehouse_principal.id,
                quantity=Decimal("15.00"),
                type="ENTRADA",
                notes="Carga inicial de inventario de prueba"
            )
            move_refresco = InventoryMovement(
                tenant_id=tenant_sol.id,
                product_id=prod_refresco.id,
                warehouse_id=warehouse_principal.id,
                quantity=Decimal("30.00"),
                type="ENTRADA",
                notes="Carga inicial de inventario de prueba"
            )
            session.add_all([move_harina, move_arroz, move_refresco])
            await session.commit()
            print("Kardex de inventario inicial registrado.")

            # --- 11. Proveedor y Deudas de Prueba ---
            supplier_polar = Supplier(
                id=uuid.UUID("91a2a3a4-b1b2-c1c2-d1d2-000000000001"),
                tenant_id=tenant_sol.id,
                name="Alimentos Polar C.A.",
                contact_name="Pedro Pérez",
                phone="0212-9998877",
                email="ventas@polar.com",
                rif="J-00002167-2"
            )
            session.add(supplier_polar)
            await session.commit()
            print("Proveedor 'Alimentos Polar' creado.")
            
            payable_debt = AccountsPayable(
                tenant_id=tenant_sol.id,
                supplier_id=supplier_polar.id,
                amount_usd=Decimal("150.00"),
                amount_ves=Decimal("5475.00"), # 150 * 36.50
                due_date=datetime.utcnow() + timedelta(days=15),
                status="PENDIENTE"
            )
            session.add(payable_debt)
            await session.commit()
            print("Cuentas por pagar creadas.")
            
            print("¡Datos de siembra cargados exitosamente!")
            
        except Exception as e:
            await session.rollback()
            print(f"Error durante la siembra de datos: {e}")
            raise e

if __name__ == "__main__":
    asyncio.run(seed_data())
