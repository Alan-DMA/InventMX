"""Add missing tenant-isolation RLS policies to the legacy schema

Revision ID: de56324d132d
Revises: e5da785414e0
Create Date: 2026-09-15 05:10:00.000000

`app/api/deps.py:get_current_user` ya fija `app.current_tenant` en cada
request (`SELECT set_config('app.current_tenant', :tenant_id, false)`),
pero ninguna tabla legacy tenía `ENABLE ROW LEVEL SECURITY` ni políticas —
por eso `GET /inventory/products` devolvía productos de cualquier tenant.

Se replica el patrón ya usado en la cadena modular (`0001_initial_core_and_rls.py`,
`0003_create_inventory_tables.py`) con una diferencia intencional: el código
legacy depende de vaciar `app.current_tenant` (`''`) para consultas globales
pre-tenant (login, registro de nuevo comercio, panel de fundadores SaaS —
ver `deps.py:41`, `auth.py:24-31`, `saas_deps.py:47,98`). La política por
tanto permite todas las filas cuando el setting está vacío/sin fijar, y
aísla estrictamente por `tenant_id` en cualquier otro caso.

`FORCE ROW LEVEL SECURITY` es obligatorio: `nexus_app` es dueño de las
tablas y Postgres omite RLS para el dueño salvo que se fuerce.
"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'de56324d132d'
down_revision: Union[str, Sequence[str], None] = 'e5da785414e0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Las 21 tablas legacy con columna `tenant_id` (ver app/models/models.py).
TENANT_SCOPED_TABLES = [
    "roles",
    "users",
    "categories",
    "products",
    "warehouses",
    "inventory",
    "inventory_movements",
    "combos",
    "sales",
    "sale_items",
    "sale_payments",
    "suppliers",
    "purchase_orders",
    "purchase_items",
    "accounts_payable",
    "cash_registers",
    "cash_sessions",
    "cash_movements",
    "subscription_invoices",
    "binance_payments_processed",
    "subscription_payment_validations",
    "catalog_pages",
    "catalog_orders",
    "audit_logs",
]

# Condición de aislamiento compartida por USING y WITH CHECK: permite todo
# cuando app.current_tenant está vacío/sin fijar (bypass global intencional
# usado por login, registro y el panel de fundadores); exige coincidencia
# exacta de tenant_id en cualquier otro caso.
_ISOLATION_CLAUSE = """(
        NULLIF(current_setting('app.current_tenant', true), '') IS NULL
        OR tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
    )"""


def upgrade() -> None:
    """Habilita y fuerza RLS con política de aislamiento por tenant en cada tabla."""
    for table in TENANT_SCOPED_TABLES:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY;")
        op.execute(f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY;")
        op.execute(f"""
            CREATE POLICY tenant_isolation_{table}_policy ON {table}
            USING {_ISOLATION_CLAUSE}
            WITH CHECK {_ISOLATION_CLAUSE};
        """)


def downgrade() -> None:
    """Revierte: elimina las políticas y desactiva RLS en cada tabla."""
    for table in TENANT_SCOPED_TABLES:
        op.execute(f"DROP POLICY IF EXISTS tenant_isolation_{table}_policy ON {table};")
        op.execute(f"ALTER TABLE {table} NO FORCE ROW LEVEL SECURITY;")
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY;")
