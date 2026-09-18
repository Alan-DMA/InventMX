"""Add default_warehouse_id to users table

Revision ID: 0016_users_default_warehouse
Revises: 0015_saas_billing_cash_denoms
Create Date: 2026-09-18 02:45:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "0016_users_default_warehouse"
down_revision: Union[str, None] = "0015_saas_billing_cash_denoms"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "public"


def upgrade() -> None:
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.users
        ADD COLUMN IF NOT EXISTS default_warehouse_id UUID
        REFERENCES {SCHEMA}.warehouses(id) ON DELETE SET NULL;
        """
    )
    op.execute(
        f"""
        CREATE INDEX IF NOT EXISTS idx_users_default_warehouse
        ON {SCHEMA}.users(default_warehouse_id);
        """
    )


def downgrade() -> None:
    op.execute(f"DROP INDEX IF EXISTS {SCHEMA}.idx_users_default_warehouse;")
    op.execute(f"ALTER TABLE {SCHEMA}.users DROP COLUMN IF EXISTS default_warehouse_id;")
