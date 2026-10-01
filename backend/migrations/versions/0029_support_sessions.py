"""Sesiones de soporte de sólo lectura — etapa 4 del Centro de soporte (Sep 2026)

Decisiones P37–P39 de Eduardo:
- Con la concesión del dueño vigente, un operador abre una sesión con motivo y
  ve la tienda en la app real del tendero (pestaña aparte), sin escribir nada.
- 30 min desde que se abre la pestaña, extensible ("Seguir 30 min más"),
  nunca más allá de la concesión.
- Enlace de un solo uso válido 10 min; sólo se guarda su huella (`link_hash`).
- El dueño ve quién entró, cuándo, cuánto duró, el motivo y las secciones
  consultadas (`sections`).

RLS del comercio con salto para el panel (igual que `support_access_grants`).

Revision ID: 0029_support_sessions
Revises: 0028_support_cases
Create Date: 2026-09-30 21:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

revision: str = "0029_support_sessions"
down_revision: Union[str, None] = "0028_support_cases"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "public"


def upgrade() -> None:
    op.execute(f"""
        CREATE TABLE {SCHEMA}.support_sessions (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            grant_id UUID NOT NULL REFERENCES {SCHEMA}.support_access_grants(id) ON DELETE CASCADE,
            operator_id UUID NOT NULL REFERENCES {SCHEMA}.platform_operators(id) ON DELETE RESTRICT,
            acting_user_id UUID NOT NULL REFERENCES {SCHEMA}.users(id) ON DELETE CASCADE,
            reason TEXT NOT NULL,
            case_id UUID NULL REFERENCES {SCHEMA}.support_cases(id) ON DELETE SET NULL,
            link_hash VARCHAR(64) NULL,
            link_expires_at TIMESTAMPTZ NULL,
            opened_at TIMESTAMPTZ NULL,
            expires_at TIMESTAMPTZ NULL,
            extensions INTEGER NOT NULL DEFAULT 0,
            sections JSONB NOT NULL DEFAULT '[]'::jsonb,
            ended_at TIMESTAMPTZ NULL,
            end_reason VARCHAR(20) NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
    """)
    op.execute(f"CREATE INDEX ix_support_sessions_tenant ON {SCHEMA}.support_sessions (tenant_id, created_at DESC);")
    op.execute(f"CREATE UNIQUE INDEX ux_support_sessions_link ON {SCHEMA}.support_sessions (link_hash) WHERE link_hash IS NOT NULL;")
    op.execute(f"ALTER TABLE {SCHEMA}.support_sessions ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.support_sessions FORCE ROW LEVEL SECURITY;")
    op.execute(f"""
        CREATE POLICY tenant_isolation_policy ON {SCHEMA}.support_sessions
        FOR ALL
        USING (
            current_setting('app.bypass_rls', true) = 'on'
            OR tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
        )
        WITH CHECK (
            current_setting('app.bypass_rls', true) = 'on'
            OR tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
        );
    """)


def downgrade() -> None:
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.support_sessions;")
