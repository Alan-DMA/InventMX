"""Create sale_payments table, payment_method_enum and update sales with payment fields

Revision ID: 0007_sale_payments
Revises: 0006_sales_and_sale_items
Create Date: 2026-09-10 08:00:00.000000

"""
# Importación de tipos para anotación de dependencias de Alembic
from typing import Sequence, Union
# Importación de operaciones de esquema de Alembic
from alembic import op
# Importación de SQLAlchemy
import sqlalchemy as sa

# Identificador de la revisión actual
revision: str = "0007_sale_payments"
# Identificador de la revisión previa (0006_sales_and_sale_items)
down_revision: Union[str, None] = "0006_sales_and_sale_items"
# Etiquetas de ramificación
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias cruzadas
depends_on: Union[str, Sequence[str], None] = None

# Nombre del esquema de base de datos
SCHEMA = "inventmx"


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. Creación del Tipo ENUM payment_method_enum
    # -------------------------------------------------------------------------
    op.execute(f"""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_type t 
                JOIN pg_namespace n ON t.typnamespace = n.oid 
                WHERE t.typname = 'payment_method_enum' AND n.nspname = '{SCHEMA}'
            ) THEN
                CREATE TYPE {SCHEMA}.payment_method_enum AS ENUM (
                    'CASH_MXN',
                    'SPEI',
                    'CODI',
                    'CARD_TPV',
                    'OTHER'
                );
            END IF;
        END $$;
    """)

    # -------------------------------------------------------------------------
    # 2. Agregar Columnas de Pago a la Tabla de Ventas (inventmx.sales)
    # -------------------------------------------------------------------------
    op.execute(f"""
        ALTER TABLE {SCHEMA}.sales 
            ADD COLUMN IF NOT EXISTS payment_method_type VARCHAR(30) NULL DEFAULT 'CASH_MXN';
    """)
    op.execute(f"""
        ALTER TABLE {SCHEMA}.sales 
            ADD COLUMN IF NOT EXISTS amount_paid_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
    """)
    op.execute(f"""
        ALTER TABLE {SCHEMA}.sales 
            ADD COLUMN IF NOT EXISTS change_returned_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
    """)

    # -------------------------------------------------------------------------
    # 3. Creación de la Tabla de Pagos de Venta (inventmx.sale_payments)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.sale_payments (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            sale_id UUID NOT NULL REFERENCES {SCHEMA}.sales(id) ON DELETE CASCADE,
            payment_method {SCHEMA}.payment_method_enum NOT NULL,
            amount_paid_mxn NUMERIC(12, 2) NOT NULL,
            change_returned_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
            reference_code VARCHAR(100) NULL,
            notes TEXT NULL,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            CONSTRAINT chk_sale_payments_amount_positive CHECK (amount_paid_mxn > 0),
            CONSTRAINT chk_sale_payments_change_non_negative CHECK (change_returned_mxn >= 0)
        );
    """)

    # Habilitar y forzar Row Level Security (RLS)
    op.execute(f"ALTER TABLE {SCHEMA}.sale_payments ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.sale_payments FORCE ROW LEVEL SECURITY;")

    # Política de aislamiento de inquilinos para sale_payments
    op.execute(f"""
        DROP POLICY IF EXISTS sale_payments_tenant_isolation_policy ON {SCHEMA}.sale_payments;
    """)
    op.execute(f"""
        CREATE POLICY sale_payments_tenant_isolation_policy ON {SCHEMA}.sale_payments
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
    """)

    # Índices de búsqueda y auditoría de pagos
    op.execute(f"""
        CREATE INDEX IF NOT EXISTS idx_sale_payments_tenant_sale ON {SCHEMA}.sale_payments (tenant_id, sale_id);
    """)
    op.execute(f"""
        CREATE INDEX IF NOT EXISTS idx_sale_payments_tenant_method ON {SCHEMA}.sale_payments (tenant_id, payment_method);
    """)
    op.execute(f"""
        CREATE INDEX IF NOT EXISTS idx_sale_payments_tenant_created ON {SCHEMA}.sale_payments (tenant_id, created_at DESC);
    """)


def downgrade() -> None:
    # -------------------------------------------------------------------------
    # Reversión de la tabla sale_payments y enum
    # -------------------------------------------------------------------------
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.sale_payments CASCADE;")
    op.execute(f"ALTER TABLE {SCHEMA}.sales DROP COLUMN IF EXISTS payment_method_type;")
    op.execute(f"ALTER TABLE {SCHEMA}.sales DROP COLUMN IF EXISTS amount_paid_mxn;")
    op.execute(f"ALTER TABLE {SCHEMA}.sales DROP COLUMN IF EXISTS change_returned_mxn;")
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.payment_method_enum;")
