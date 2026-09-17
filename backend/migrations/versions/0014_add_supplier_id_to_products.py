"""Add supplier_id to products table

Revision ID: 0014_add_supplier_id_to_products
Revises: 0013_community_b2b_catalog
Create Date: 2026-09-14 18:48:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "0014_add_supplier_id_to_products"
down_revision: Union[str, None] = "0013_community_b2b_catalog"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "public"


def upgrade() -> None:
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.products 
        ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES {SCHEMA}.suppliers(id) ON DELETE SET NULL;
        """
    )
    op.execute(
        f"""
        CREATE INDEX IF NOT EXISTS idx_products_tenant_supplier 
        ON {SCHEMA}.products(tenant_id, supplier_id);
        """
    )


def downgrade() -> None:
    op.execute(f"DROP INDEX IF EXISTS {SCHEMA}.idx_products_tenant_supplier;")
    op.execute(f"ALTER TABLE {SCHEMA}.products DROP COLUMN IF EXISTS supplier_id;")
