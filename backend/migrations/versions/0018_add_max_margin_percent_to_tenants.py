"""Add max_margin_percent to tenants (precio máximo sugerido, fallback de margen)

Revision ID: 0018_add_max_margin_percent
Revises: 0017_add_sale_refund_columns
Create Date: 2026-09-18 17:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "0018_add_max_margin_percent"
down_revision: Union[str, None] = "0017_add_sale_refund_columns"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "public"


def upgrade() -> None:
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.tenants
        ADD COLUMN IF NOT EXISTS max_margin_percent NUMERIC(5, 2)
        NOT NULL DEFAULT 40.00;
        """
    )
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.tenants
        ADD CONSTRAINT chk_tenants_max_margin_percent_non_negative
        CHECK (max_margin_percent >= 0);
        """
    )


def downgrade() -> None:
    op.execute(f"ALTER TABLE {SCHEMA}.tenants DROP CONSTRAINT IF EXISTS chk_tenants_max_margin_percent_non_negative;")
    op.execute(f"ALTER TABLE {SCHEMA}.tenants DROP COLUMN IF EXISTS max_margin_percent;")
