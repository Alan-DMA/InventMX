"""Add refund tracking columns to sales and sale_items

Revision ID: 0017_add_sale_refund_columns
Revises: 0016_users_default_warehouse
Create Date: 2026-09-18 04:10:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "0017_add_sale_refund_columns"
down_revision: Union[str, None] = "0016_users_default_warehouse"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "public"


def upgrade() -> None:
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.sale_items
        ADD COLUMN IF NOT EXISTS refunded_quantity NUMERIC(12, 3)
        NOT NULL DEFAULT 0;
        """
    )
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.sales
        ADD COLUMN IF NOT EXISTS refunded_amount_mxn NUMERIC(12, 2)
        NOT NULL DEFAULT 0;
        """
    )
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.sale_items
        ADD CONSTRAINT chk_sale_items_refunded_qty_non_negative
        CHECK (refunded_quantity >= 0);
        """
    )
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.sales
        ADD CONSTRAINT chk_sales_refunded_amount_non_negative
        CHECK (refunded_amount_mxn >= 0);
        """
    )


def downgrade() -> None:
    op.execute(f"ALTER TABLE {SCHEMA}.sales DROP CONSTRAINT IF EXISTS chk_sales_refunded_amount_non_negative;")
    op.execute(f"ALTER TABLE {SCHEMA}.sale_items DROP CONSTRAINT IF EXISTS chk_sale_items_refunded_qty_non_negative;")
    op.execute(f"ALTER TABLE {SCHEMA}.sales DROP COLUMN IF EXISTS refunded_amount_mxn;")
    op.execute(f"ALTER TABLE {SCHEMA}.sale_items DROP COLUMN IF EXISTS refunded_quantity;")
