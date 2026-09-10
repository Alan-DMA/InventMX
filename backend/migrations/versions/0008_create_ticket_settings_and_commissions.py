"""Create ticket_settings, commission_type_enum and sale_commissions tables

Revision ID: 0008_tickets_and_commissions
Revises: 0007_sale_payments
Create Date: 2026-09-10 09:00:00.000000

"""
# Importación de tipos para anotación de dependencias de Alembic
from typing import Sequence, Union
# Importación de operaciones de esquema de Alembic
from alembic import op
# Importación de SQLAlchemy
import sqlalchemy as sa

# Identificador de la revisión actual
revision: str = "0008_tickets_and_commissions"
# Identificador de la revisión previa (0007_sale_payments)
down_revision: Union[str, None] = "0007_sale_payments"
# Etiquetas de ramificación
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias cruzadas
depends_on: Union[str, Sequence[str], None] = None

# Nombre del esquema de base de datos
SCHEMA = "inventmx"


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. Creación de la Tabla de Configuración de Tickets (inventmx.ticket_settings)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.ticket_settings (
            tenant_id UUID PRIMARY KEY REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            business_name VARCHAR(150) NULL,
            legal_name VARCHAR(150) NULL,
            rfc VARCHAR(13) NULL,
            address TEXT NULL,
            phone VARCHAR(30) NULL,
            email VARCHAR(100) NULL,
            footer_message TEXT NULL DEFAULT '¡Gracias por su compra!',
            paper_width_mm INT NOT NULL DEFAULT 58,
            show_savings BOOLEAN NOT NULL DEFAULT TRUE,
            show_cashier_name BOOLEAN NOT NULL DEFAULT TRUE,
            show_taxes BOOLEAN NOT NULL DEFAULT FALSE,
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            CONSTRAINT chk_ticket_paper_width CHECK (paper_width_mm IN (58, 80))
        );
    """)

    # Habilitar y forzar Row Level Security (RLS) en ticket_settings
    op.execute(f"ALTER TABLE {SCHEMA}.ticket_settings ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.ticket_settings FORCE ROW LEVEL SECURITY;")

    # Política de aislamiento RLS en ticket_settings
    op.execute(f"DROP POLICY IF EXISTS ticket_settings_tenant_isolation_policy ON {SCHEMA}.ticket_settings;")
    op.execute(f"""
        CREATE POLICY ticket_settings_tenant_isolation_policy ON {SCHEMA}.ticket_settings
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
    """)

    # -------------------------------------------------------------------------
    # 2. Creación del Tipo ENUM commission_type_enum
    # -------------------------------------------------------------------------
    op.execute(f"""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_type t 
                JOIN pg_namespace n ON t.typnamespace = n.oid 
                WHERE t.typname = 'commission_type_enum' AND n.nspname = '{SCHEMA}'
            ) THEN
                CREATE TYPE {SCHEMA}.commission_type_enum AS ENUM (
                    'PERCENTAGE_SALE',
                    'PERCENTAGE_PROFIT',
                    'FIXED_PER_SALE'
                );
            END IF;
        END $$;
    """)

    # -------------------------------------------------------------------------
    # 3. Creación de la Tabla de Comisiones de Venta (inventmx.sale_commissions)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.sale_commissions (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            sale_id UUID NOT NULL REFERENCES {SCHEMA}.sales(id) ON DELETE CASCADE,
            user_id UUID NOT NULL REFERENCES {SCHEMA}.users(id) ON DELETE CASCADE,
            commission_type {SCHEMA}.commission_type_enum NOT NULL DEFAULT 'PERCENTAGE_SALE',
            commission_rate NUMERIC(5, 2) NOT NULL DEFAULT 0.00,
            base_amount_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
            commission_amount_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
            is_settled BOOLEAN NOT NULL DEFAULT FALSE,
            settled_at TIMESTAMP WITH TIME ZONE NULL,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            CONSTRAINT chk_sale_commissions_rate_non_negative CHECK (commission_rate >= 0),
            CONSTRAINT chk_sale_commissions_amount_non_negative CHECK (commission_amount_mxn >= 0)
        );
    """)

    # Habilitar y forzar Row Level Security (RLS) en sale_commissions
    op.execute(f"ALTER TABLE {SCHEMA}.sale_commissions ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.sale_commissions FORCE ROW LEVEL SECURITY;")

    # Política de aislamiento RLS en sale_commissions
    op.execute(f"DROP POLICY IF EXISTS sale_commissions_tenant_isolation_policy ON {SCHEMA}.sale_commissions;")
    op.execute(f"""
        CREATE POLICY sale_commissions_tenant_isolation_policy ON {SCHEMA}.sale_commissions
            FOR ALL
            USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
            WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
    """)

    # Índices para consultas y reportería de comisiones
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_sale_commissions_tenant_user ON {SCHEMA}.sale_commissions (tenant_id, user_id);")
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_sale_commissions_tenant_sale ON {SCHEMA}.sale_commissions (tenant_id, sale_id);")
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_sale_commissions_tenant_created ON {SCHEMA}.sale_commissions (tenant_id, created_at DESC);")


def downgrade() -> None:
    # Eliminación de índices y tablas
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.sale_commissions CASCADE;")
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.commission_type_enum CASCADE;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.ticket_settings CASCADE;")
