"""Vigencia de la suscripción por comercio: "vigente hasta" y de dónde vino (Sep 2026)

Modelo prepago de Eduardo (P9–P13): se paga una suscripción → vale un mes →
gracia → bloqueo; al pagar, un mes nuevo desde el día del pago. La fuente del
periodo (prueba, cortesía, manual, pasarela o Google Play) queda registrada para
que el día de integrar Google Play sólo haya que alimentar esta misma fecha.

A los comercios que ya existen se les da un mes desde hoy: ninguno se bloquea de
golpe al activar el ciclo (CA-P14).

Revision ID: 0026_tenant_entitlement
Revises: 0025_platform_admin_foundation
Create Date: 2026-09-28 16:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

revision: str = "0026_tenant_entitlement"
down_revision: Union[str, None] = "0025_platform_admin_foundation"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "public"


def upgrade() -> None:
    op.execute(f"ALTER TABLE {SCHEMA}.tenants ADD COLUMN paid_until TIMESTAMPTZ NULL;")
    op.execute(f"ALTER TABLE {SCHEMA}.tenants ADD COLUMN subscription_source VARCHAR(20) NULL;")
    op.execute(f"""
        UPDATE {SCHEMA}.tenants
        SET paid_until = now() + interval '1 month', subscription_source = 'TRIAL'
        WHERE paid_until IS NULL;
    """)


def downgrade() -> None:
    op.execute(f"ALTER TABLE {SCHEMA}.tenants DROP COLUMN IF EXISTS subscription_source;")
    op.execute(f"ALTER TABLE {SCHEMA}.tenants DROP COLUMN IF EXISTS paid_until;")
