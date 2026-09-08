"""Create inventory tables with PostgreSQL RLS and pg_trgm extension

Revision ID: 0003_inventory_tables
Revises: 0002_seed_rbac
Create Date: 2026-09-08 17:30:00.000000

"""
# Importación de tipos para anotación de dependencias de Alembic
from typing import Sequence, Union
# Importación de operaciones de esquema de Alembic
from alembic import op
# Importación de SQLAlchemy
import sqlalchemy as sa

# Identificador de la revisión actual
revision: str = "0003_inventory_tables"
# Identificador de la revisión previa (0002_seed_rbac)
down_revision: Union[str, None] = "0002_seed_rbac"
# Etiquetas de ramificación
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias cruzadas
depends_on: Union[str, Sequence[str], None] = None

# Nombre del esquema de base de datos
SCHEMA = "inventmx"


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. Habilitación de la extensión pg_trgm para búsqueda difusa (fuzzy search)
    # -------------------------------------------------------------------------
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm;")

    # -------------------------------------------------------------------------
    # 2. Creación de la Tabla de Categorías (categories)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.categories (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            name VARCHAR(100) NOT NULL,
            description TEXT,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
    """)

    # Habilitar y forzar Row Level Security en categories
    op.execute(f"ALTER TABLE {SCHEMA}.categories ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.categories FORCE ROW LEVEL SECURITY;")

    # Crear política de aislamiento RLS para categories (Permissive por defecto)
    op.execute(f"""
        DO $$
        BEGIN
            DROP POLICY IF EXISTS tenant_isolation_categories_policy ON {SCHEMA}.categories;
            CREATE POLICY tenant_isolation_categories_policy ON {SCHEMA}.categories
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
        END$$;
    """)

    # Índice de tenant para optimizar consultas de categorías
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_categories_tenant ON {SCHEMA}.categories(tenant_id);")

    # -------------------------------------------------------------------------
    # 3. Creación de la Tabla de Almacenes (warehouses)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.warehouses (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            name VARCHAR(150) NOT NULL,
            is_default BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
    """)

    # Habilitar y forzar Row Level Security en warehouses
    op.execute(f"ALTER TABLE {SCHEMA}.warehouses ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.warehouses FORCE ROW LEVEL SECURITY;")

    # Crear política de aislamiento RLS para warehouses
    op.execute(f"""
        DO $$
        BEGIN
            DROP POLICY IF EXISTS tenant_isolation_warehouses_policy ON {SCHEMA}.warehouses;
            CREATE POLICY tenant_isolation_warehouses_policy ON {SCHEMA}.warehouses
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
        END$$;
    """)

    # Índice de tenant para almacenes
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_warehouses_tenant ON {SCHEMA}.warehouses(tenant_id);")

    # -------------------------------------------------------------------------
    # 4. Creación de la Tabla de Productos (products) con Moneda Base MXN
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.products (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            category_id UUID REFERENCES {SCHEMA}.categories(id) ON DELETE SET NULL,
            name VARCHAR(255) NOT NULL,
            price_mxn NUMERIC(12, 2) NOT NULL CHECK (price_mxn >= 0),
            cost_mxn NUMERIC(12, 2) DEFAULT 0.00 CHECK (cost_mxn >= 0),
            cost_usd_import NUMERIC(12, 4) DEFAULT NULL,
            sku VARCHAR(50) NOT NULL,
            barcode VARCHAR(50),
            min_stock_alert NUMERIC(10, 2) DEFAULT 5.00 CHECK (min_stock_alert >= 0),
            image_url VARCHAR(500),
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            CONSTRAINT uq_products_tenant_sku UNIQUE (tenant_id, sku)
        );
    """)

    # Habilitar y forzar Row Level Security en products
    op.execute(f"ALTER TABLE {SCHEMA}.products ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.products FORCE ROW LEVEL SECURITY;")

    # Crear política de aislamiento RLS para products
    op.execute(f"""
        DO $$
        BEGIN
            DROP POLICY IF EXISTS tenant_isolation_products_policy ON {SCHEMA}.products;
            CREATE POLICY tenant_isolation_products_policy ON {SCHEMA}.products
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
        END$$;
    """)

    # Índices optimizados para productos
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_products_tenant ON {SCHEMA}.products(tenant_id);")
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_products_barcode ON {SCHEMA}.products(tenant_id, barcode);")
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_products_category ON {SCHEMA}.products(tenant_id, category_id);")
    # Índice GIN con trigramas para búsqueda ultra-rápida por nombre (< 10ms)
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_products_name_trgm ON {SCHEMA}.products USING gin (name gin_trgm_ops);")

    # -------------------------------------------------------------------------
    # 5. Creación de la Tabla de Existencias por Almacén (product_stocks)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.product_stocks (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            product_id UUID NOT NULL REFERENCES {SCHEMA}.products(id) ON DELETE CASCADE,
            warehouse_id UUID NOT NULL REFERENCES {SCHEMA}.warehouses(id) ON DELETE RESTRICT,
            current_stock NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
            reserved_stock NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            CONSTRAINT uq_product_stocks_tenant_prod_wh UNIQUE (tenant_id, product_id, warehouse_id)
        );
    """)

    # Habilitar y forzar Row Level Security en product_stocks
    op.execute(f"ALTER TABLE {SCHEMA}.product_stocks ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.product_stocks FORCE ROW LEVEL SECURITY;")

    # Crear política de aislamiento RLS para product_stocks
    op.execute(f"""
        DO $$
        BEGIN
            DROP POLICY IF EXISTS tenant_isolation_product_stocks_policy ON {SCHEMA}.product_stocks;
            CREATE POLICY tenant_isolation_product_stocks_policy ON {SCHEMA}.product_stocks
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
        END$$;
    """)

    # Índices para existencias
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_product_stocks_tenant ON {SCHEMA}.product_stocks(tenant_id);")
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_product_stocks_prod ON {SCHEMA}.product_stocks(tenant_id, product_id);")


def downgrade() -> None:
    # Eliminación ordenada respetando integridad referencial
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.product_stocks CASCADE;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.products CASCADE;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.warehouses CASCADE;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.categories CASCADE;")
