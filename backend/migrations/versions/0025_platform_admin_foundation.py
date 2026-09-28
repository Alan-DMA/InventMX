"""Panel de plataforma, Fase 1: identidad de operadores, TOTP y bitácora (Sep 2026)

- `platform_operators`: Alan y Eduardo como operadores de la plataforma. No
  pertenecen a ningún comercio ni pasan por RLS; se crean sólo por script.
- `platform_recovery_codes`: códigos de un solo uso para cuando falta el
  teléfono con Google Authenticator (se guardan con hash).
- `platform_audit_log`: bitácora de sólo anexar, encadenada con hash. Un trigger
  rechaza UPDATE y DELETE: ni la aplicación ni un error de código la reescriben.
- `users.last_login_at`: "última actividad" de un comercio sin mirar su contenido.
- Métodos de pago manuales: efectivo, SPEI capturado y cortesía.

Revision ID: 0025_platform_admin_foundation
Revises: 0024_warehouses_is_active
Create Date: 2026-09-27 23:50:00.000000

"""
# Importación de tipos para anotación de dependencias de Alembic
from typing import Sequence, Union
# Importación de operaciones de Alembic
from alembic import op

# Identificador único de la revisión actual
revision: str = "0025_platform_admin_foundation"
# Identificador de la revisión previa de la cual depende esta migración
down_revision: Union[str, None] = "0024_warehouses_is_active"
# Etiquetas de ramificación (None en flujo lineal)
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias entre migraciones paralelas (None)
depends_on: Union[str, Sequence[str], None] = None

# Nombre constante del esquema PostgreSQL donde residen las tablas
SCHEMA = "public"


def upgrade() -> None:
    # Operadores de la plataforma (fuera de todo comercio)
    op.execute(f"""
        CREATE TABLE {SCHEMA}.platform_operators (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            email VARCHAR(255) NOT NULL UNIQUE,
            full_name VARCHAR(150) NOT NULL,
            hashed_password VARCHAR(255) NOT NULL,
            totp_secret_encrypted TEXT NULL,
            totp_enabled_at TIMESTAMPTZ NULL,
            totp_last_step BIGINT NULL,
            failed_attempts INTEGER NOT NULL DEFAULT 0,
            locked_until TIMESTAMPTZ NULL,
            is_active BOOLEAN NOT NULL DEFAULT TRUE,
            last_login_at TIMESTAMPTZ NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
    """)

    # Códigos de recuperación de un solo uso
    op.execute(f"""
        CREATE TABLE {SCHEMA}.platform_recovery_codes (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            operator_id UUID NOT NULL REFERENCES {SCHEMA}.platform_operators(id) ON DELETE CASCADE,
            code_hash VARCHAR(64) NOT NULL,
            used_at TIMESTAMPTZ NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
    """)
    op.execute(
        f"CREATE INDEX idx_platform_recovery_codes_operator ON {SCHEMA}.platform_recovery_codes (operator_id);"
    )

    # Bitácora de sólo anexar, encadenada con hash
    op.execute(f"""
        CREATE TABLE {SCHEMA}.platform_audit_log (
            id BIGSERIAL PRIMARY KEY,
            occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            operator_id UUID NULL REFERENCES {SCHEMA}.platform_operators(id) ON DELETE RESTRICT,
            action VARCHAR(60) NOT NULL,
            target_tenant_id UUID NULL,
            target_type VARCHAR(40) NULL,
            target_id VARCHAR(64) NULL,
            reason TEXT NULL,
            details JSONB NOT NULL DEFAULT '{{}}'::jsonb,
            ip_address VARCHAR(64) NULL,
            user_agent VARCHAR(255) NULL,
            prev_hash CHAR(64) NULL,
            row_hash CHAR(64) NOT NULL
        );
    """)
    op.execute(
        f"CREATE INDEX idx_platform_audit_tenant ON {SCHEMA}.platform_audit_log (target_tenant_id, occurred_at DESC);"
    )
    op.execute(
        f"CREATE INDEX idx_platform_audit_occurred ON {SCHEMA}.platform_audit_log (occurred_at DESC);"
    )
    op.execute(f"""
        CREATE OR REPLACE FUNCTION {SCHEMA}.platform_audit_log_immutable()
        RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
            RAISE EXCEPTION 'platform_audit_log es de sólo anexar: no se permite %', TG_OP;
        END;
        $$;
    """)
    op.execute(f"""
        CREATE TRIGGER trg_platform_audit_log_immutable
        BEFORE UPDATE OR DELETE ON {SCHEMA}.platform_audit_log
        FOR EACH ROW EXECUTE FUNCTION {SCHEMA}.platform_audit_log_immutable();
    """)
    # También contra TRUNCATE, que no dispara triggers por fila
    op.execute(f"""
        CREATE TRIGGER trg_platform_audit_log_no_truncate
        BEFORE TRUNCATE ON {SCHEMA}.platform_audit_log
        FOR EACH STATEMENT EXECUTE FUNCTION {SCHEMA}.platform_audit_log_immutable();
    """)

    # Última actividad de las personas de un comercio
    op.execute(f"ALTER TABLE {SCHEMA}.users ADD COLUMN last_login_at TIMESTAMPTZ NULL;")

    # Métodos de pago que confirman los fundadores a mano
    for value in ("CASH", "MANUAL_SPEI", "COURTESY"):
        op.execute(f"ALTER TYPE {SCHEMA}.saas_payment_method_enum ADD VALUE IF NOT EXISTS '{value}';")


def downgrade() -> None:
    # Los valores de un ENUM no se pueden quitar en PostgreSQL: se conservan.
    op.execute(f"ALTER TABLE {SCHEMA}.users DROP COLUMN IF EXISTS last_login_at;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.platform_audit_log;")
    op.execute(f"DROP FUNCTION IF EXISTS {SCHEMA}.platform_audit_log_immutable();")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.platform_recovery_codes;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.platform_operators;")
