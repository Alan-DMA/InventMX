"""Centro de soporte: códigos de acceso, exportaciones, aprobaciones y accesos concedidos (Sep 2026)

- `users.must_change_password`: quien entra con un código de un solo uso queda
  obligado a poner contraseña nueva antes de usar la app (P16).
- `tenants.lock_reason`: por qué está bloqueado un comercio — `NONPAYMENT` (lo
  pone el ciclo) o `ABUSE` (suspensión de soporte, P17). Un pago o un regalo de
  días nunca levanta una suspensión por abuso.
- `login_codes`: códigos que sustituyen a la contraseña, hasheados; el propio
  dueño los pide (`SELF`) o soporte tras validarlo (`ASSISTED`, P21/P22). Se leen
  antes de iniciar sesión, sin comercio en contexto: sin RLS, como `tenants`.
- `platform_export_jobs`: exportación de datos al correo del dueño (P18).
- `platform_approval_requests`: acciones de dos personas (P4). Sin FK al
  comercio: la solicitud sobrevive a la eliminación que aprueba.
- `support_access_grants`: el dueño concede acceso de soporte (P2/P18). Es del
  comercio: RLS como el resto de sus tablas.

Revision ID: 0027_support_center
Revises: 0026_tenant_entitlement
Create Date: 2026-09-28 21:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

revision: str = "0027_support_center"
down_revision: Union[str, None] = "0026_tenant_entitlement"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "public"


def upgrade() -> None:
    op.execute(f"ALTER TABLE {SCHEMA}.users ADD COLUMN must_change_password BOOLEAN NOT NULL DEFAULT FALSE;")
    op.execute(f"ALTER TABLE {SCHEMA}.tenants ADD COLUMN lock_reason VARCHAR(20) NULL;")
    # Los bloqueos previos venían del ciclo o del panel por falta de pago
    op.execute(f"""
        UPDATE {SCHEMA}.tenants SET lock_reason = 'NONPAYMENT'
        WHERE status <> 'ACTIVE' AND lock_reason IS NULL;
    """)

    op.execute(f"""
        CREATE TABLE {SCHEMA}.login_codes (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES {SCHEMA}.users(id) ON DELETE CASCADE,
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            code_hash VARCHAR(64) NOT NULL,
            origin VARCHAR(10) NOT NULL CHECK (origin IN ('SELF', 'ASSISTED')),
            created_by_operator_id UUID NULL REFERENCES {SCHEMA}.platform_operators(id) ON DELETE RESTRICT,
            expires_at TIMESTAMPTZ NOT NULL,
            used_at TIMESTAMPTZ NULL,
            invalidated_at TIMESTAMPTZ NULL,
            failed_attempts INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
    """)
    op.execute(f"CREATE INDEX ix_login_codes_user ON {SCHEMA}.login_codes (user_id, created_at DESC);")

    op.execute(f"""
        CREATE TABLE {SCHEMA}.platform_export_jobs (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            requested_by UUID NOT NULL REFERENCES {SCHEMA}.platform_operators(id) ON DELETE RESTRICT,
            status VARCHAR(10) NOT NULL CHECK (status IN ('PENDING', 'SENT', 'FAILED')),
            error TEXT NULL,
            size_bytes BIGINT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            finished_at TIMESTAMPTZ NULL
        );
    """)
    op.execute(f"CREATE INDEX ix_platform_export_jobs_tenant ON {SCHEMA}.platform_export_jobs (tenant_id, created_at DESC);")

    op.execute(f"""
        CREATE TABLE {SCHEMA}.platform_approval_requests (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            kind VARCHAR(30) NOT NULL,
            tenant_id UUID NOT NULL,
            tenant_name VARCHAR(150) NOT NULL,
            requested_by UUID NOT NULL REFERENCES {SCHEMA}.platform_operators(id) ON DELETE RESTRICT,
            reason TEXT NOT NULL,
            status VARCHAR(10) NOT NULL CHECK (status IN ('PENDING', 'APPROVED', 'CANCELLED')),
            decided_by UUID NULL REFERENCES {SCHEMA}.platform_operators(id) ON DELETE RESTRICT,
            decision_reason TEXT NULL,
            decided_at TIMESTAMPTZ NULL,
            expires_at TIMESTAMPTZ NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
    """)
    op.execute(f"""
        CREATE UNIQUE INDEX ux_platform_approval_pending
        ON {SCHEMA}.platform_approval_requests (kind, tenant_id) WHERE status = 'PENDING';
    """)

    op.execute(f"""
        CREATE TABLE {SCHEMA}.support_access_grants (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            granted_by_user_id UUID NOT NULL REFERENCES {SCHEMA}.users(id) ON DELETE CASCADE,
            expires_at TIMESTAMPTZ NOT NULL,
            revoked_at TIMESTAMPTZ NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
    """)
    op.execute(f"CREATE INDEX ix_support_access_grants_tenant ON {SCHEMA}.support_access_grants (tenant_id, created_at DESC);")
    op.execute(f"ALTER TABLE {SCHEMA}.support_access_grants ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.support_access_grants FORCE ROW LEVEL SECURITY;")
    op.execute(f"""
        CREATE POLICY tenant_isolation_policy ON {SCHEMA}.support_access_grants
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
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.support_access_grants;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.platform_approval_requests;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.platform_export_jobs;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.login_codes;")
    op.execute(f"ALTER TABLE {SCHEMA}.tenants DROP COLUMN IF EXISTS lock_reason;")
    op.execute(f"ALTER TABLE {SCHEMA}.users DROP COLUMN IF EXISTS must_change_password;")
