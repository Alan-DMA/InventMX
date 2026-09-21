"""Create catalog_orders (pedidos registrados desde la vitrina pública, RF-24)

Revision ID: 0019_create_catalog_orders
Revises: 0018_add_max_margin_percent
Create Date: 2026-09-20 10:00:00.000000

"""
from typing import Sequence, Union
from alembic import op

revision: str = "0019_create_catalog_orders"
down_revision: Union[str, None] = "0018_add_max_margin_percent"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "public"


def upgrade() -> None:
    op.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.catalog_orders (
            id UUID PRIMARY KEY,
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            folio VARCHAR(20) NOT NULL,
            customer_name VARCHAR(100) NOT NULL,
            customer_phone VARCHAR(20),
            delivery_method VARCHAR(20) NOT NULL,
            delivery_address VARCHAR(300),
            payment_method VARCHAR(30) NOT NULL,
            cash_tendered_mxn NUMERIC(12, 2),
            order_notes TEXT,
            items JSONB NOT NULL DEFAULT '[]'::jsonb,
            subtotal_mxn NUMERIC(12, 2) NOT NULL,
            delivery_fee_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
            total_mxn NUMERIC(12, 2) NOT NULL,
            change_mxn NUMERIC(12, 2),
            item_count INTEGER NOT NULL DEFAULT 0,
            formatted_text TEXT NOT NULL,
            wa_link TEXT NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT uq_catalog_orders_tenant_folio UNIQUE (tenant_id, folio),
            CONSTRAINT chk_catalog_orders_subtotal_non_negative CHECK (subtotal_mxn >= 0),
            CONSTRAINT chk_catalog_orders_total_non_negative CHECK (total_mxn >= 0)
        );
        """
    )
    op.execute(
        f"CREATE INDEX IF NOT EXISTS ix_catalog_orders_tenant_id ON {SCHEMA}.catalog_orders (tenant_id);"
    )
    op.execute(
        f"CREATE INDEX IF NOT EXISTS ix_catalog_orders_tenant_created ON {SCHEMA}.catalog_orders (tenant_id, created_at DESC);"
    )
    # RLS multi-tenant — mismo patrón que el resto de tablas (0003): la clave
    # de sesión es app.current_tenant, la que inyecta set_tenant_context().
    op.execute(f"ALTER TABLE {SCHEMA}.catalog_orders ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.catalog_orders FORCE ROW LEVEL SECURITY;")
    op.execute(
        f"""
        DROP POLICY IF EXISTS tenant_isolation_catalog_orders_policy ON {SCHEMA}.catalog_orders;
        CREATE POLICY tenant_isolation_catalog_orders_policy ON {SCHEMA}.catalog_orders
        FOR ALL
        USING (
            current_setting('app.bypass_rls', true) = 'on'
            OR tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
        )
        WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
        """
    )


def downgrade() -> None:
    op.execute(f"DROP POLICY IF EXISTS tenant_isolation_catalog_orders_policy ON {SCHEMA}.catalog_orders;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.catalog_orders;")
