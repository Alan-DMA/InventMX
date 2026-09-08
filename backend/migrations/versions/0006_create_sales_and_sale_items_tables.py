"""Create sales and sale_items tables with RLS policies and POS transaction support

Revision ID: 0006_sales_and_sale_items
Revises: 0005_seed_catalog
Create Date: 2026-09-08 20:00:00.000000

"""
# Importación de tipos para anotación de dependencias de Alembic
from typing import Sequence, Union
# Importación de operaciones de esquema de Alembic
from alembic import op
# Importación de SQLAlchemy
import sqlalchemy as sa

# Identificador de la revisión actual
revision: str = "0006_sales_and_sale_items"
# Identificador de la revisión previa (0005_seed_catalog)
down_revision: Union[str, None] = "0005_seed_catalog"
# Etiquetas de ramificación
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias cruzadas
depends_on: Union[str, Sequence[str], None] = None

# Nombre del esquema de base de datos
SCHEMA = "inventmx"


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. Creación del Tipo ENUM sale_status_enum
    # -------------------------------------------------------------------------
    op.execute(f"""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_type t 
                JOIN pg_namespace n ON t.typnamespace = n.oid 
                WHERE t.typname = 'sale_status_enum' AND n.nspname = '{SCHEMA}'
            ) THEN
                CREATE TYPE {SCHEMA}.sale_status_enum AS ENUM (
                    'DRAFT',
                    'PENDING_PAYMENT',
                    'PAID',
                    'COMPLETED',
                    'CANCELLED',
                    'REFUNDED'
                );
            END IF;

            -- Agregar valores SALE_CANCEL y SALE_RETURN al enum de movimientos si no existen
            ALTER TYPE {SCHEMA}.movement_type_enum ADD VALUE IF NOT EXISTS 'SALE_CANCEL';
            ALTER TYPE {SCHEMA}.movement_type_enum ADD VALUE IF NOT EXISTS 'SALE_RETURN';
        END $$;
    """)

    # -------------------------------------------------------------------------
    # 2. Creación de la Tabla de Ventas (inventmx.sales)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.sales (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            cashier_id UUID NOT NULL REFERENCES {SCHEMA}.users(id) ON DELETE RESTRICT,
            warehouse_id UUID NOT NULL REFERENCES {SCHEMA}.warehouses(id) ON DELETE RESTRICT,
            client_id UUID NULL,
            folio VARCHAR(50) NOT NULL,
            status {SCHEMA}.sale_status_enum NOT NULL DEFAULT 'COMPLETED',
            subtotal_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
            discount_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
            tax_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
            total_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
            total_cost_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
            notes TEXT NULL,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            CONSTRAINT chk_sales_total_non_negative CHECK (total_mxn >= 0),
            CONSTRAINT chk_sales_subtotal_non_negative CHECK (subtotal_mxn >= 0),
            CONSTRAINT chk_sales_discount_non_negative CHECK (discount_mxn >= 0),
            CONSTRAINT chk_sales_total_cost_non_negative CHECK (total_cost_mxn >= 0)
        );

        -- Habilitar y forzar Row Level Security (RLS)
        ALTER TABLE {SCHEMA}.sales ENABLE ROW LEVEL SECURITY;
        ALTER TABLE {SCHEMA}.sales FORCE ROW LEVEL SECURITY;

        -- Política de aislamiento de inquilinos para sales
        DROP POLICY IF EXISTS sales_tenant_isolation_policy ON {SCHEMA}.sales;
        CREATE POLICY sales_tenant_isolation_policy ON {SCHEMA}.sales
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

        -- Índices de auditoría y búsqueda rápida
        CREATE INDEX IF NOT EXISTS idx_sales_tenant_created ON {SCHEMA}.sales (tenant_id, created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_sales_tenant_folio ON {SCHEMA}.sales (tenant_id, folio);
        CREATE INDEX IF NOT EXISTS idx_sales_tenant_cashier ON {SCHEMA}.sales (tenant_id, cashier_id);
        CREATE INDEX IF NOT EXISTS idx_sales_tenant_status ON {SCHEMA}.sales (tenant_id, status);
    """)

    # -------------------------------------------------------------------------
    # 3. Creación de la Tabla de Partidas de Venta (inventmx.sale_items)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.sale_items (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            sale_id UUID NOT NULL REFERENCES {SCHEMA}.sales(id) ON DELETE CASCADE,
            product_id UUID NULL REFERENCES {SCHEMA}.products(id) ON DELETE SET NULL,
            combo_id UUID NULL REFERENCES {SCHEMA}.combos(id) ON DELETE SET NULL,
            product_name VARCHAR(255) NOT NULL,
            product_sku VARCHAR(50) NULL,
            quantity NUMERIC(12, 3) NOT NULL,
            unit_price_mxn NUMERIC(12, 2) NOT NULL,
            unit_cost_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
            subtotal_mxn NUMERIC(12, 2) NOT NULL,
            discount_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
            total_mxn NUMERIC(12, 2) NOT NULL,
            is_on_the_fly BOOLEAN NOT NULL DEFAULT FALSE,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            CONSTRAINT chk_sale_items_qty_positive CHECK (quantity > 0),
            CONSTRAINT chk_sale_items_price_non_negative CHECK (unit_price_mxn >= 0),
            CONSTRAINT chk_sale_items_cost_non_negative CHECK (unit_cost_mxn >= 0),
            CONSTRAINT chk_sale_items_total_non_negative CHECK (total_mxn >= 0)
        );

        -- Habilitar y forzar Row Level Security (RLS)
        ALTER TABLE {SCHEMA}.sale_items ENABLE ROW LEVEL SECURITY;
        ALTER TABLE {SCHEMA}.sale_items FORCE ROW LEVEL SECURITY;

        -- Política de aislamiento de inquilinos para sale_items
        DROP POLICY IF EXISTS sale_items_tenant_isolation_policy ON {SCHEMA}.sale_items;
        CREATE POLICY sale_items_tenant_isolation_policy ON {SCHEMA}.sale_items
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

        -- Índices de optimización de consultas
        CREATE INDEX IF NOT EXISTS idx_sale_items_tenant_sale ON {SCHEMA}.sale_items (tenant_id, sale_id);
        CREATE INDEX IF NOT EXISTS idx_sale_items_tenant_product ON {SCHEMA}.sale_items (tenant_id, product_id);
        CREATE INDEX IF NOT EXISTS idx_sale_items_tenant_combo ON {SCHEMA}.sale_items (tenant_id, combo_id);
    """)


def downgrade() -> None:
    # -------------------------------------------------------------------------
    # Reversión de tablas de ventas
    # -------------------------------------------------------------------------
    op.execute(f"""
        DROP TABLE IF EXISTS {SCHEMA}.sale_items CASCADE;
        DROP TABLE IF EXISTS {SCHEMA}.sales CASCADE;
        DROP TYPE IF EXISTS {SCHEMA}.sale_status_enum;
    """)
