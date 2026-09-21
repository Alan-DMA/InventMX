"""Ciclo de vida de pedidos web: estado, visto, edición con historial y venta ligada

Revision ID: 0020_catalog_orders_lifecycle
Revises: 0019_create_catalog_orders
Create Date: 2026-09-20 14:00:00.000000

"""
from typing import Sequence, Union
from alembic import op

revision: str = "0020_catalog_orders_lifecycle"
down_revision: Union[str, None] = "0019_create_catalog_orders"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "public"


def upgrade() -> None:
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.catalog_orders
            ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'NEW',
            ADD COLUMN IF NOT EXISTS status_changed_at TIMESTAMPTZ,
            ADD COLUMN IF NOT EXISTS cancel_reason VARCHAR(40),
            ADD COLUMN IF NOT EXISTS seen_at TIMESTAMPTZ,
            ADD COLUMN IF NOT EXISTS seen_by UUID REFERENCES {SCHEMA}.users(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS attended_by UUID REFERENCES {SCHEMA}.users(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ,
            ADD COLUMN IF NOT EXISTS edited_by UUID REFERENCES {SCHEMA}.users(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS revisions JSONB NOT NULL DEFAULT '[]'::jsonb,
            ADD COLUMN IF NOT EXISTS sale_id UUID REFERENCES {SCHEMA}.sales(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
        """
    )
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.catalog_orders
            DROP CONSTRAINT IF EXISTS chk_catalog_orders_status;
        ALTER TABLE {SCHEMA}.catalog_orders
            ADD CONSTRAINT chk_catalog_orders_status
            CHECK (status IN ('NEW', 'READY', 'DELIVERED', 'CANCELLED'));
        """
    )
    op.execute(
        f"CREATE INDEX IF NOT EXISTS ix_catalog_orders_tenant_status ON {SCHEMA}.catalog_orders (tenant_id, status, created_at DESC);"
    )


def downgrade() -> None:
    op.execute(f"DROP INDEX IF EXISTS {SCHEMA}.ix_catalog_orders_tenant_status;")
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.catalog_orders
            DROP CONSTRAINT IF EXISTS chk_catalog_orders_status,
            DROP COLUMN IF EXISTS status,
            DROP COLUMN IF EXISTS status_changed_at,
            DROP COLUMN IF EXISTS cancel_reason,
            DROP COLUMN IF EXISTS seen_at,
            DROP COLUMN IF EXISTS seen_by,
            DROP COLUMN IF EXISTS attended_by,
            DROP COLUMN IF EXISTS edited_at,
            DROP COLUMN IF EXISTS edited_by,
            DROP COLUMN IF EXISTS revisions,
            DROP COLUMN IF EXISTS sale_id,
            DROP COLUMN IF EXISTS updated_at;
        """
    )
