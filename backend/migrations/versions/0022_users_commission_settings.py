"""Add per-employee commission settings to users (RF-10)

Revision ID: 0022_users_commission_settings
Revises: 0021_catalog_orders_access_key
Create Date: 2026-09-21 13:10:00.000000

"""
from typing import Sequence, Union
from alembic import op

revision: str = "0022_users_commission_settings"
down_revision: Union[str, None] = "0021_catalog_orders_access_key"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "public"


def upgrade() -> None:
    # Reutiliza el enum de sale_commissions (0008): el esquema por empleado
    # define cómo se calcula cada asiento que el checkout registra.
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.users
        ADD COLUMN IF NOT EXISTS commission_type {SCHEMA}.commission_type_enum
            NOT NULL DEFAULT 'PERCENTAGE_SALE',
        ADD COLUMN IF NOT EXISTS commission_rate NUMERIC(5, 2) NOT NULL DEFAULT 0.00;
        """
    )
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.users
        ADD CONSTRAINT chk_users_commission_rate_non_negative CHECK (commission_rate >= 0);
        """
    )


def downgrade() -> None:
    op.execute(f"ALTER TABLE {SCHEMA}.users DROP CONSTRAINT IF EXISTS chk_users_commission_rate_non_negative;")
    op.execute(f"ALTER TABLE {SCHEMA}.users DROP COLUMN IF EXISTS commission_rate;")
    op.execute(f"ALTER TABLE {SCHEMA}.users DROP COLUMN IF EXISTS commission_type;")
