"""Baja lógica de almacenes (Ajustes operativos, D7 — Sep 2026)

Un almacén no se borra: se da de baja cuando está vacío y sin pendientes, y
se puede reactivar. Lo histórico (ventas, turnos, compras, Kardex) sigue
apuntando a él y cuenta en "Todos".

Revision ID: 0024_warehouses_is_active
Revises: 0023_rls_roles
Create Date: 2026-09-27 19:00:00.000000

"""
# Importación de tipos para anotación de dependencias de Alembic
from typing import Sequence, Union
# Importación de operaciones de Alembic y tipos de SQLAlchemy
from alembic import op
import sqlalchemy as sa

# Identificador único de la revisión actual
revision: str = "0024_warehouses_is_active"
# Identificador de la revisión previa de la cual depende esta migración
down_revision: Union[str, None] = "0023_rls_roles"
# Etiquetas de ramificación (None en flujo lineal)
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias entre migraciones paralelas (None)
depends_on: Union[str, Sequence[str], None] = None

# Nombre constante del esquema PostgreSQL donde residen las tablas
SCHEMA = "public"


def upgrade() -> None:
    # Todos los almacenes existentes nacen activos
    op.add_column(
        "warehouses",
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        schema=SCHEMA,
    )


def downgrade() -> None:
    op.drop_column("warehouses", "is_active", schema=SCHEMA)
