"""Create combos, kardex movements, and stock reservations tables with RLS

Revision ID: 0004_combos_kardex
Revises: 0003_inventory_tables
Create Date: 2026-09-08 17:40:00.000000

"""
# Importación de tipos para anotación de dependencias de Alembic
from typing import Sequence, Union
# Importación de operaciones de esquema de Alembic
from alembic import op
# Importación de SQLAlchemy
import sqlalchemy as sa

# Identificador de la revisión actual
revision: str = "0004_combos_kardex"
# Identificador de la revisión previa (0003_inventory_tables)
down_revision: Union[str, None] = "0003_inventory_tables"
# Etiquetas de ramificación
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias cruzadas
depends_on: Union[str, Sequence[str], None] = None

# Nombre del esquema de base de datos
SCHEMA = "inventmx"


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. Creación de Enums de Movimientos de Inventario y Estado de Reservas
    # -------------------------------------------------------------------------
    op.execute(f"""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_type t 
                JOIN pg_namespace n ON t.typnamespace = n.oid 
                WHERE t.typname = 'movement_type_enum' AND n.nspname = '{SCHEMA}'
            ) THEN
                CREATE TYPE {SCHEMA}.movement_type_enum AS ENUM (
                    'PURCHASE_ENTRY',
                    'SALE_EXIT',
                    'ADJUSTMENT_IN',
                    'ADJUSTMENT_OUT',
                    'TRANSFER_IN',
                    'TRANSFER_OUT',
                    'WASTE_MERMA',
                    'RESERVATION_HOLD',
                    'RESERVATION_RELEASE'
                );
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM pg_type t 
                JOIN pg_namespace n ON t.typnamespace = n.oid 
                WHERE t.typname = 'reservation_status_enum' AND n.nspname = '{SCHEMA}'
            ) THEN
                CREATE TYPE {SCHEMA}.reservation_status_enum AS ENUM (
                    'PENDING',
                    'COMMITTED',
                    'RELEASED',
                    'EXPIRED'
                );
            END IF;
        END$$;
    """)

    # -------------------------------------------------------------------------
    # 2. Creación de la Tabla de Combos / Promociones (combos)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.combos (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            name VARCHAR(255) NOT NULL,
            description TEXT,
            price_mxn NUMERIC(12, 2) NOT NULL CHECK (price_mxn >= 0),
            sku VARCHAR(50) NOT NULL,
            barcode VARCHAR(50),
            image_url VARCHAR(500),
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            CONSTRAINT uq_combos_tenant_sku UNIQUE (tenant_id, sku)
        );
    """)

    # Habilitar y forzar Row Level Security en combos
    op.execute(f"ALTER TABLE {SCHEMA}.combos ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.combos FORCE ROW LEVEL SECURITY;")

    # Crear política de aislamiento RLS para combos
    op.execute(f"""
        DO $$
        BEGIN
            DROP POLICY IF EXISTS tenant_isolation_combos_policy ON {SCHEMA}.combos;
            CREATE POLICY tenant_isolation_combos_policy ON {SCHEMA}.combos
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
        END$$;
    """)

    # Índices para combos
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_combos_tenant ON {SCHEMA}.combos(tenant_id);")
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_combos_barcode ON {SCHEMA}.combos(tenant_id, barcode);")

    # -------------------------------------------------------------------------
    # 3. Creación de la Tabla de Ítems de Combo (combo_items)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.combo_items (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            combo_id UUID NOT NULL REFERENCES {SCHEMA}.combos(id) ON DELETE CASCADE,
            product_id UUID NOT NULL REFERENCES {SCHEMA}.products(id) ON DELETE RESTRICT,
            quantity NUMERIC(10, 2) NOT NULL CHECK (quantity > 0),
            CONSTRAINT uq_combo_items_combo_product UNIQUE (combo_id, product_id)
        );
    """)

    # Habilitar y forzar Row Level Security en combo_items
    op.execute(f"ALTER TABLE {SCHEMA}.combo_items ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.combo_items FORCE ROW LEVEL SECURITY;")

    # Crear política de aislamiento RLS para combo_items
    op.execute(f"""
        DO $$
        BEGIN
            DROP POLICY IF EXISTS tenant_isolation_combo_items_policy ON {SCHEMA}.combo_items;
            CREATE POLICY tenant_isolation_combo_items_policy ON {SCHEMA}.combo_items
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
        END$$;
    """)

    # Índices para combo_items
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_combo_items_combo ON {SCHEMA}.combo_items(combo_id);")
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_combo_items_product ON {SCHEMA}.combo_items(product_id);")

    # -------------------------------------------------------------------------
    # 4. Creación de la Tabla de Kardex Inmutable (inventory_movements)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.inventory_movements (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            product_id UUID NOT NULL REFERENCES {SCHEMA}.products(id) ON DELETE CASCADE,
            warehouse_id UUID NOT NULL REFERENCES {SCHEMA}.warehouses(id) ON DELETE RESTRICT,
            from_warehouse_id UUID REFERENCES {SCHEMA}.warehouses(id) ON DELETE SET NULL,
            to_warehouse_id UUID REFERENCES {SCHEMA}.warehouses(id) ON DELETE SET NULL,
            user_id UUID REFERENCES {SCHEMA}.users(id) ON DELETE SET NULL,
            movement_type {SCHEMA}.movement_type_enum NOT NULL,
            quantity NUMERIC(10, 2) NOT NULL,
            previous_stock NUMERIC(10, 2) NOT NULL,
            new_stock NUMERIC(10, 2) NOT NULL,
            unit_cost_mxn NUMERIC(12, 2) DEFAULT 0.00,
            reference_id UUID,
            notes TEXT,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
    """)

    # Habilitar y forzar Row Level Security en inventory_movements
    op.execute(f"ALTER TABLE {SCHEMA}.inventory_movements ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.inventory_movements FORCE ROW LEVEL SECURITY;")

    # Crear política de aislamiento RLS para inventory_movements
    op.execute(f"""
        DO $$
        BEGIN
            DROP POLICY IF EXISTS tenant_isolation_movements_policy ON {SCHEMA}.inventory_movements;
            CREATE POLICY tenant_isolation_movements_policy ON {SCHEMA}.inventory_movements
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
        END$$;
    """)

    # Índices optimizados para auditoría en Kardex
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_movements_tenant ON {SCHEMA}.inventory_movements(tenant_id);")
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_movements_product ON {SCHEMA}.inventory_movements(tenant_id, product_id);")
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_movements_warehouse ON {SCHEMA}.inventory_movements(tenant_id, warehouse_id);")
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_movements_created ON {SCHEMA}.inventory_movements(tenant_id, created_at);")

    # -------------------------------------------------------------------------
    # 5. Creación de la Tabla de Reservas de Stock con TTL (stock_reservations)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.stock_reservations (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            product_id UUID NOT NULL REFERENCES {SCHEMA}.products(id) ON DELETE CASCADE,
            warehouse_id UUID NOT NULL REFERENCES {SCHEMA}.warehouses(id) ON DELETE RESTRICT,
            quantity NUMERIC(10, 2) NOT NULL CHECK (quantity > 0),
            status {SCHEMA}.reservation_status_enum NOT NULL DEFAULT 'PENDING',
            reference_id UUID,
            expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
    """)

    # Habilitar y forzar Row Level Security en stock_reservations
    op.execute(f"ALTER TABLE {SCHEMA}.stock_reservations ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.stock_reservations FORCE ROW LEVEL SECURITY;")

    # Crear política de aislamiento RLS para stock_reservations
    op.execute(f"""
        DO $$
        BEGIN
            DROP POLICY IF EXISTS tenant_isolation_reservations_policy ON {SCHEMA}.stock_reservations;
            CREATE POLICY tenant_isolation_reservations_policy ON {SCHEMA}.stock_reservations
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
        END$$;
    """)

    # Índices para reservas y barrido de TTL
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_reservations_tenant ON {SCHEMA}.stock_reservations(tenant_id);")
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_reservations_expires ON {SCHEMA}.stock_reservations(status, expires_at);")


def downgrade() -> None:
    # Eliminación ordenada respetando integridad referencial
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.stock_reservations CASCADE;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.inventory_movements CASCADE;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.combo_items CASCADE;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.combos CASCADE;")
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.reservation_status_enum;")
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.movement_type_enum;")
