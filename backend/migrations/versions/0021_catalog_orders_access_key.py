"""Clave de acceso al ticket público de pedidos web (contra adivinar folios)

Revision ID: 0021_catalog_orders_access_key
Revises: 0020_catalog_orders_lifecycle
Create Date: 2026-09-20 21:00:00.000000

"""
from typing import Sequence, Union
from alembic import op

revision: str = "0021_catalog_orders_access_key"
down_revision: Union[str, None] = "0020_catalog_orders_lifecycle"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "public"


def upgrade() -> None:
    # El folio (P-YYMMDD-XXXX) es adivinable: 65,536 combinaciones por día y
    # tienda. Con él solo, cualquiera leería nombre, teléfono y dirección de
    # otros clientes. La clave viaja únicamente en el enlace del chat.
    op.execute(
        f"""
        ALTER TABLE {SCHEMA}.catalog_orders
            ADD COLUMN IF NOT EXISTS access_key VARCHAR(32);
        -- RLS forzado: el UPDATE no ve filas y el WITH CHECK exige tenant. Se
        -- apaga sólo durante el relleno (DDL del dueño, misma transacción).
        ALTER TABLE {SCHEMA}.catalog_orders DISABLE ROW LEVEL SECURITY;
        UPDATE {SCHEMA}.catalog_orders
            SET access_key = substr(md5(random()::text || id::text), 1, 12)
            WHERE access_key IS NULL;
        ALTER TABLE {SCHEMA}.catalog_orders ENABLE ROW LEVEL SECURITY;
        ALTER TABLE {SCHEMA}.catalog_orders FORCE ROW LEVEL SECURITY;
        ALTER TABLE {SCHEMA}.catalog_orders
            ALTER COLUMN access_key SET NOT NULL;
        """
    )


def downgrade() -> None:
    op.execute(f"ALTER TABLE {SCHEMA}.catalog_orders DROP COLUMN IF EXISTS access_key;")
