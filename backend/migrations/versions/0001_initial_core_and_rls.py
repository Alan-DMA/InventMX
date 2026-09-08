"""Initial core tenancy and RLS migration

Revision ID: 0001_core_rls
Revises: 
Create Date: 2026-09-08 17:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, ENUM as PG_ENUM

# revision identifiers, used by Alembic.
revision: str = "0001_core_rls"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "inventmx"


def upgrade() -> None:
    # 1. Asegurar schema y extensiones
    op.execute(f'CREATE SCHEMA IF NOT EXISTS {SCHEMA};')
    op.execute('CREATE EXTENSION IF NOT EXISTS "uuid-ossp";')
    op.execute('CREATE EXTENSION IF NOT EXISTS "pg_trgm";')

    # 2. Creación segura de Enums en el schema inventmx
    op.execute(f"""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON t.typnamespace = n.oid WHERE t.typname = 'tenant_plan_enum' AND n.nspname = '{SCHEMA}') THEN
                CREATE TYPE {SCHEMA}.tenant_plan_enum AS ENUM ('EMPRENDEDOR', 'COMERCIO', 'CORPORATIVO');
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON t.typnamespace = n.oid WHERE t.typname = 'tenant_status_enum' AND n.nspname = '{SCHEMA}') THEN
                CREATE TYPE {SCHEMA}.tenant_status_enum AS ENUM ('ACTIVE', 'SOFT_LOCK', 'HARD_LOCK');
            END IF;
        END$$;
    """)

    # 3. Tabla tenants
    op.create_table(
        "tenants",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("name", sa.String(150), nullable=False),
        sa.Column("slug", sa.String(100), nullable=False, unique=True),
        sa.Column("plan_id", PG_ENUM("EMPRENDEDOR", "COMERCIO", "CORPORATIVO", name="tenant_plan_enum", schema=SCHEMA, create_type=False), nullable=False, server_default="EMPRENDEDOR"),
        sa.Column("status", PG_ENUM("ACTIVE", "SOFT_LOCK", "HARD_LOCK", name="tenant_status_enum", schema=SCHEMA, create_type=False), nullable=False, server_default="ACTIVE"),
        sa.Column("rfc", sa.String(13), nullable=True),
        sa.Column("legal_name", sa.String(200), nullable=True),
        sa.Column("enable_usd_secondary", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        schema=SCHEMA,
    )
    op.create_index("idx_tenants_slug", "tenants", ["slug"], schema=SCHEMA)
    op.create_index("idx_tenants_status", "tenants", ["status"], schema=SCHEMA)

    # 4. Tabla roles
    op.create_table(
        "roles",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=True),
        sa.Column("name", sa.String(50), nullable=False),
        sa.Column("description", sa.String(255), nullable=False),
        schema=SCHEMA,
    )
    op.create_index("idx_roles_tenant_id", "roles", ["tenant_id"], schema=SCHEMA)
    op.create_index("idx_roles_name", "roles", ["name"], schema=SCHEMA)

    # 5. Tabla permissions
    op.create_table(
        "permissions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("code", sa.String(100), nullable=False, unique=True),
        sa.Column("description", sa.String(255), nullable=False),
        schema=SCHEMA,
    )
    op.create_index("idx_permissions_code", "permissions", ["code"], schema=SCHEMA)

    # 6. Tabla role_permissions
    op.create_table(
        "role_permissions",
        sa.Column("role_id", UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.roles.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("permission_id", UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.permissions.id", ondelete="CASCADE"), primary_key=True),
        schema=SCHEMA,
    )

    # 7. Tabla users
    op.create_table(
        "users",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("hashed_password", sa.String(255), nullable=False),
        sa.Column("full_name", sa.String(150), nullable=False),
        sa.Column("role_id", UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.roles.id"), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        schema=SCHEMA,
    )
    op.create_index("idx_users_tenant_id", "users", ["tenant_id"], schema=SCHEMA)
    op.create_index("idx_users_email", "users", ["email"], schema=SCHEMA)
    op.create_index("idx_users_tenant_email", "users", ["tenant_id", "email"], unique=True, schema=SCHEMA)

    # 8. Activación de Row-Level Security (RLS) en PostgreSQL
    op.execute(f"ALTER TABLE {SCHEMA}.users ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.users FORCE ROW LEVEL SECURITY;")

    # 9. Creación de la Política de Aislamiento Multi-tenant (Permissive)
    op.execute(f"""
        CREATE POLICY tenant_isolation_policy ON {SCHEMA}.users
        FOR ALL
        USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
        WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
    """)

    # 10. Inserción de Roles Globales del Sistema
    op.execute(f"""
        INSERT INTO {SCHEMA}.roles (id, tenant_id, name, description) VALUES
        ('a0000000-0000-0000-0000-000000000001', NULL, 'OWNER', 'Dueño del comercio con acceso total'),
        ('a0000000-0000-0000-0000-000000000002', NULL, 'ADMIN', 'Administrador de tienda y catálogo'),
        ('a0000000-0000-0000-0000-000000000003', NULL, 'CASHIER', 'Cajero para punto de venta y corte de caja'),
        ('a0000000-0000-0000-0000-000000000004', NULL, 'WAREHOUSE', 'Encargado de almacén y recepción de compras')
        ON CONFLICT (id) DO NOTHING;
    """)


def downgrade() -> None:
    op.execute(f"DROP POLICY IF EXISTS tenant_isolation_policy ON {SCHEMA}.users;")
    op.execute(f"ALTER TABLE {SCHEMA}.users DISABLE ROW LEVEL SECURITY;")
    op.drop_table("users", schema=SCHEMA)
    op.drop_table("role_permissions", schema=SCHEMA)
    op.drop_table("permissions", schema=SCHEMA)
    op.drop_table("roles", schema=SCHEMA)
    op.drop_table("tenants", schema=SCHEMA)
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.tenant_status_enum;")
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.tenant_plan_enum;")
