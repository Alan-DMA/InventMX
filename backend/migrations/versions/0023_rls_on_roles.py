"""Row-Level Security en roles: los roles propios de un comercio no cruzan de tenant

Los cuatro roles del sistema viven con `tenant_id IS NULL` y los ve todo el mundo;
desde la Fase B de permisos (Sep 2026) un comercio puede tener su **copia** de un rol
(clone-on-write), y esa copia es suya. Hasta ahora `roles` era la única tabla del
núcleo sin política: el aislamiento dependía de que cada consulta filtrara a mano.

Revision ID: 0023_rls_roles
Revises: 0022_users_commission_settings
Create Date: 2026-09-23 13:10:00.000000

"""
# Importación de tipos para anotación de dependencias de Alembic
from typing import Sequence, Union
# Importación de operaciones de Alembic para manipulación del esquema
from alembic import op

# Identificador único de la revisión actual
revision: str = "0023_rls_roles"
# Identificador de la revisión previa de la cual depende esta migración
down_revision: Union[str, None] = "0022_users_commission_settings"
# Etiquetas de ramificación (None en flujo lineal)
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias entre migraciones paralelas (None)
depends_on: Union[str, Sequence[str], None] = None

# Nombre constante del esquema PostgreSQL donde residen las tablas
SCHEMA = "public"


def upgrade() -> None:
    # Activación de RLS sobre la tabla de roles
    op.execute(f"ALTER TABLE {SCHEMA}.roles ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.roles FORCE ROW LEVEL SECURITY;")

    # Política de aislamiento: cada comercio ve los roles globales del sistema
    # (tenant_id IS NULL, de sólo lectura para él) más los suyos propios. El
    # WITH CHECK impide crear o mover un rol al tenant de otro; los roles
    # globales sólo se siembran por migración, con el bypass activo.
    op.execute(f"""
        CREATE POLICY tenant_isolation_policy ON {SCHEMA}.roles
        FOR ALL
        USING (
            current_setting('app.bypass_rls', true) = 'on'
            OR tenant_id IS NULL
            OR tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
        )
        WITH CHECK (
            current_setting('app.bypass_rls', true) = 'on'
            OR tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
        );
    """)

    # `role_permissions` cuelga de un rol: se protege por la misma vía, mirando
    # el tenant del rol al que pertenece la fila.
    op.execute(f"ALTER TABLE {SCHEMA}.role_permissions ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.role_permissions FORCE ROW LEVEL SECURITY;")
    op.execute(f"""
        CREATE POLICY tenant_isolation_policy ON {SCHEMA}.role_permissions
        FOR ALL
        USING (
            current_setting('app.bypass_rls', true) = 'on'
            OR EXISTS (
                SELECT 1 FROM {SCHEMA}.roles r
                WHERE r.id = role_id
                  AND (
                      r.tenant_id IS NULL
                      OR r.tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
                  )
            )
        )
        WITH CHECK (
            current_setting('app.bypass_rls', true) = 'on'
            OR EXISTS (
                SELECT 1 FROM {SCHEMA}.roles r
                WHERE r.id = role_id
                  AND r.tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
            )
        );
    """)


def downgrade() -> None:
    op.execute(f"DROP POLICY IF EXISTS tenant_isolation_policy ON {SCHEMA}.role_permissions;")
    op.execute(f"ALTER TABLE {SCHEMA}.role_permissions DISABLE ROW LEVEL SECURITY;")
    op.execute(f"DROP POLICY IF EXISTS tenant_isolation_policy ON {SCHEMA}.roles;")
    op.execute(f"ALTER TABLE {SCHEMA}.roles DISABLE ROW LEVEL SECURITY;")
