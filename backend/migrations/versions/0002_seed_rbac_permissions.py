"""Seed RBAC permissions and default roles matrix

Revision ID: 0002_seed_rbac
Revises: 0001_core_rls
Create Date: 2026-09-08 17:15:00.000000

"""
# Importación de tipos para anotación de dependencias de Alembic
from typing import Sequence, Union
# Importación de operaciones de Alembic para manipulación del esquema
from alembic import op
# Importación de SQLAlchemy para construcción de sentencias
import sqlalchemy as sa

# Identificador único de la revisión actual
revision: str = "0002_seed_rbac"
# Identificador de la revisión previa de la cual depende esta migración
down_revision: Union[str, None] = "0001_core_rls"
# Etiquetas de ramificación (None en flujo lineal)
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias entre migraciones paralelas (None)
depends_on: Union[str, Sequence[str], None] = None

# Nombre constante del esquema PostgreSQL donde residen las tablas
SCHEMA = "inventmx"


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. Sembrado del Catálogo de Permisos Granulares (Doc. Maestro Sec. 9.2)
    # -------------------------------------------------------------------------
    # Ejecutamos la inserción con ON CONFLICT DO NOTHING para garantizar idempotencia
    op.execute(f"""
        INSERT INTO {SCHEMA}.permissions (id, code, description) VALUES
        -- Permisos del Módulo de Inventario
        (gen_random_uuid(), 'inventory.view', 'Consultar listado de productos, categorías y existencias'),
        (gen_random_uuid(), 'inventory.create', 'Registrar nuevos productos en el catálogo maestro'),
        (gen_random_uuid(), 'inventory.edit_price', 'Modificar precios de venta en MXN y costos'),
        (gen_random_uuid(), 'inventory.adjust_stock', 'Realizar ajustes de stock físico, traslados y mermas'),
        (gen_random_uuid(), 'inventory.delete', 'Desactivar o eliminar productos del inventario'),
        
        -- Permisos del Módulo de Ventas y Punto de Venta (POS)
        (gen_random_uuid(), 'sales.view', 'Consultar historial de ventas y notas emitidas'),
        (gen_random_uuid(), 'sales.checkout', 'Procesar ventas en punto de venta y emitir notas de venta'),
        (gen_random_uuid(), 'sales.apply_discount', 'Aplicar descuentos o cortesías durante el cobro'),
        (gen_random_uuid(), 'sales.cancel', 'Cancelar ventas registradas y procesar devoluciones'),
        
        -- Permisos del Módulo de Caja y Tesorería
        (gen_random_uuid(), 'cash.view', 'Consultar estado de caja y arqueo de turnos'),
        (gen_random_uuid(), 'cash.open_session', 'Abrir turno de caja con fondo inicial en MXN'),
        (gen_random_uuid(), 'cash.close_session', 'Cerrar turno de caja y realizar desglose con cono Banxico'),
        (gen_random_uuid(), 'cash.manual_movement', 'Registrar entradas o salidas de efectivo de caja chica'),
        
        -- Permisos del Módulo de Compras y Proveedores
        (gen_random_uuid(), 'purchases.view', 'Consultar compras y directorio de proveedores'),
        (gen_random_uuid(), 'purchases.create', 'Registrar órdenes de compra y recepción de mercancía'),
        (gen_random_uuid(), 'purchases.pay_credit', 'Abonar a cuentas por pagar a distribuidores'),
        
        -- Permisos del Módulo de Analítica y Reportes
        (gen_random_uuid(), 'reports.view_basic', 'Consultar reportes básicos de ventas y stock'),
        (gen_random_uuid(), 'reports.view_advanced', 'Consultar analítica avanzada, márgenes netos y KPIs'),
        
        -- Permisos del Módulo de Configuración y Administración
        (gen_random_uuid(), 'settings.manage_users', 'Crear, editar y desactivar cuentas de empleados'),
        (gen_random_uuid(), 'settings.manage_store', 'Modificar configuración comercial de la tienda'),
        (gen_random_uuid(), 'settings.billing', 'Administrar suscripción SaaS y canales de pago')
        ON CONFLICT (code) DO NOTHING;
    """)

    # -------------------------------------------------------------------------
    # 2. Asignación de Permisos a los Roles Globales del Sistema
    # -------------------------------------------------------------------------
    
    # Rol ADMIN: Todos los permisos excepto facturación SaaS (settings.billing)
    op.execute(f"""
        INSERT INTO {SCHEMA}.role_permissions (role_id, permission_id)
        SELECT 'a0000000-0000-0000-0000-000000000002', id
        FROM {SCHEMA}.permissions
        WHERE code != 'settings.billing'
        ON CONFLICT DO NOTHING;
    """)

    # Rol CASHIER: Operación diaria de caja y punto de venta
    op.execute(f"""
        INSERT INTO {SCHEMA}.role_permissions (role_id, permission_id)
        SELECT 'a0000000-0000-0000-0000-000000000003', id
        FROM {SCHEMA}.permissions
        WHERE code IN (
            'inventory.view',
            'sales.view',
            'sales.checkout',
            'cash.view',
            'cash.open_session',
            'cash.close_session',
            'cash.manual_movement'
        )
        ON CONFLICT DO NOTHING;
    """)

    # Rol WAREHOUSE: Control de almacén, existencias y compras
    op.execute(f"""
        INSERT INTO {SCHEMA}.role_permissions (role_id, permission_id)
        SELECT 'a0000000-0000-0000-0000-000000000004', id
        FROM {SCHEMA}.permissions
        WHERE code IN (
            'inventory.view',
            'inventory.create',
            'inventory.adjust_stock',
            'purchases.view',
            'purchases.create'
        )
        ON CONFLICT DO NOTHING;
    """)


def downgrade() -> None:
    # Eliminación de relaciones role_permissions
    op.execute(f"DELETE FROM {SCHEMA}.role_permissions;")
    # Eliminación del catálogo de permisos
    op.execute(f"DELETE FROM {SCHEMA}.permissions;")
