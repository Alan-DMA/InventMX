"""Create cash_shifts and cash_movements tables with RLS and enum types

Revision ID: 0009_cash_shifts_and_movements
Revises: 0008_tickets_and_commissions
Create Date: 2026-09-10 10:00:00.000000

"""
# Importación de tipos para anotación de dependencias de Alembic
from typing import Sequence, Union
# Importación de operaciones de esquema de Alembic
from alembic import op
# Importación de SQLAlchemy
import sqlalchemy as sa
# Importación de dialecto PostgreSQL para tipos específicos (UUID, ENUM)
from sqlalchemy.dialects import postgresql

# Identificador de la revisión actual
revision: str = "0009_cash_shifts_and_movements"
# Identificador de la revisión previa (0008_tickets_and_commissions)
down_revision: Union[str, None] = "0008_tickets_and_commissions"
# Etiquetas de ramificación
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias cruzadas
depends_on: Union[str, Sequence[str], None] = None

# Nombre del esquema de base de datos
SCHEMA = "inventmx"


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. Creación de Tipos ENUM de PostgreSQL para Turnos y Movimientos
    # -------------------------------------------------------------------------
    
    # Declaración del tipo enum para el estado del turno (OPEN, CLOSED)
    shift_status_enum = postgresql.ENUM(
        "OPEN",
        "CLOSED",
        name="shift_status_enum",
        schema=SCHEMA,
        create_type=False,
    )
    # Ejecución de creación del tipo enum en PostgreSQL de forma idempotente
    op.execute(
        f"DO $$ BEGIN "
        f"  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE t.typname = 'shift_status_enum' AND n.nspname = '{SCHEMA}') THEN "
        f"    CREATE TYPE {SCHEMA}.shift_status_enum AS ENUM ('OPEN', 'CLOSED'); "
        f"  END IF; "
        f"END $$;"
    )

    # Declaración del tipo enum para el tipo de movimiento de efectivo (CASH_IN, CASH_OUT)
    cash_movement_type_enum = postgresql.ENUM(
        "CASH_IN",
        "CASH_OUT",
        name="cash_movement_type_enum",
        schema=SCHEMA,
        create_type=False,
    )
    # Ejecución de creación del tipo enum en PostgreSQL de forma idempotente
    op.execute(
        f"DO $$ BEGIN "
        f"  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE t.typname = 'cash_movement_type_enum' AND n.nspname = '{SCHEMA}') THEN "
        f"    CREATE TYPE {SCHEMA}.cash_movement_type_enum AS ENUM ('CASH_IN', 'CASH_OUT'); "
        f"  END IF; "
        f"END $$;"
    )

    # -------------------------------------------------------------------------
    # 2. Creación de la Tabla de Turnos de Caja (inventmx.cash_shifts)
    # -------------------------------------------------------------------------
    op.create_table(
        "cash_shifts",
        # Identificador único universal del turno
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        # Identificador del inquilino propietario para aislamiento multi-tenant
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        # Identificador del cajero responsable del turno
        sa.Column("cashier_id", postgresql.UUID(as_uuid=True), nullable=False),
        # Identificador de la sucursal o almacén asignado al turno
        sa.Column("warehouse_id", postgresql.UUID(as_uuid=True), nullable=True),
        # Estado actual del turno (OPEN, CLOSED)
        sa.Column("status", shift_status_enum, nullable=False, server_default="OPEN"),
        # Fondo de caja inicial recibido para cambio en Pesos Mexicanos
        sa.Column("opening_balance_mxn", sa.Numeric(12, 2), nullable=False, server_default="0.00"),
        # Conteo físico de dinero en efectivo ingresado en el arqueo de cierre
        sa.Column("counted_cash_mxn", sa.Numeric(12, 2), nullable=True),
        # Monto teórico calculado por el sistema en Pesos Mexicanos
        sa.Column("expected_cash_mxn", sa.Numeric(12, 2), nullable=True),
        # Diferencia resultante del arqueo (counted_cash - expected_cash)
        sa.Column("difference_mxn", sa.Numeric(12, 2), nullable=True),
        # Marca de tiempo de apertura del turno
        sa.Column("opened_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        # Marca de tiempo de cierre formal del turno
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True),
        # Identificador del usuario que autorizó o ejecutó el cierre del turno
        sa.Column("closed_by_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        # Observaciones y notas de auditoría del turno
        sa.Column("notes", sa.Text(), nullable=True),
        # Marca de tiempo de creación del registro
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        # Marca de tiempo de última actualización
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now(), onupdate=sa.func.now()),
        # Restricción de clave foránea a tenants con borrado en cascada
        sa.ForeignKeyConstraint(
            ["tenant_id"],
            [f"{SCHEMA}.tenants.id"],
            ondelete="CASCADE",
            name="fk_cash_shifts_tenant_id",
        ),
        # Restricción de clave foránea a usuarios (cajero) con restricción
        sa.ForeignKeyConstraint(
            ["cashier_id"],
            [f"{SCHEMA}.users.id"],
            ondelete="RESTRICT",
            name="fk_cash_shifts_cashier_id",
        ),
        # Restricción de clave foránea a almacenes con set null
        sa.ForeignKeyConstraint(
            ["warehouse_id"],
            [f"{SCHEMA}.warehouses.id"],
            ondelete="SET NULL",
            name="fk_cash_shifts_warehouse_id",
        ),
        # Restricción de clave foránea a usuarios (quien cierra) con set null
        sa.ForeignKeyConstraint(
            ["closed_by_user_id"],
            [f"{SCHEMA}.users.id"],
            ondelete="SET NULL",
            name="fk_cash_shifts_closed_by_user_id",
        ),
        # Restricción de chequeo: el fondo de caja inicial debe ser no negativo
        sa.CheckConstraint("opening_balance_mxn >= 0", name="chk_cash_shifts_opening_balance_positive"),
        schema=SCHEMA,
    )

    # Creación de índices optimizados para cash_shifts
    op.create_index(
        "idx_cash_shifts_tenant_cashier_status",
        "cash_shifts",
        ["tenant_id", "cashier_id", "status"],
        schema=SCHEMA,
    )
    op.create_index(
        "idx_cash_shifts_tenant_created",
        "cash_shifts",
        ["tenant_id", "created_at"],
        schema=SCHEMA,
    )

    # -------------------------------------------------------------------------
    # 3. Creación de la Tabla de Movimientos de Caja (inventmx.cash_movements)
    # -------------------------------------------------------------------------
    op.create_table(
        "cash_movements",
        # Identificador único universal del movimiento de caja
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        # Identificador del inquilino propietario para aislamiento multi-tenant
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        # Identificador del turno de caja al que pertenece el movimiento
        sa.Column("shift_id", postgresql.UUID(as_uuid=True), nullable=False),
        # Tipo de movimiento (CASH_IN = Entrada, CASH_OUT = Salida/Gasto)
        sa.Column("movement_type", cash_movement_type_enum, nullable=False),
        # Monto del movimiento en Pesos Mexicanos (siempre positivo)
        sa.Column("amount_mxn", sa.Numeric(12, 2), nullable=False),
        # Razón o motivo descriptivo del movimiento de efectivo
        sa.Column("reason", sa.String(255), nullable=False),
        # Notas adicionales o justificación detallada
        sa.Column("notes", sa.Text(), nullable=True),
        # Usuario supervisor o administrador que autorizó el movimiento (opcional)
        sa.Column("authorized_by_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        # Usuario cajero u operador que registró el movimiento
        sa.Column("created_by_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        # Marca de tiempo de registro del movimiento
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        # Restricción de clave foránea a tenants con borrado en cascada
        sa.ForeignKeyConstraint(
            ["tenant_id"],
            [f"{SCHEMA}.tenants.id"],
            ondelete="CASCADE",
            name="fk_cash_movements_tenant_id",
        ),
        # Restricción de clave foránea a turnos de caja con borrado en cascada
        sa.ForeignKeyConstraint(
            ["shift_id"],
            [f"{SCHEMA}.cash_shifts.id"],
            ondelete="CASCADE",
            name="fk_cash_movements_shift_id",
        ),
        # Restricción de clave foránea a usuarios (autorizador) con set null
        sa.ForeignKeyConstraint(
            ["authorized_by_user_id"],
            [f"{SCHEMA}.users.id"],
            ondelete="SET NULL",
            name="fk_cash_movements_authorized_by_user_id",
        ),
        # Restricción de clave foránea a usuarios (creador) con restricción
        sa.ForeignKeyConstraint(
            ["created_by_user_id"],
            [f"{SCHEMA}.users.id"],
            ondelete="RESTRICT",
            name="fk_cash_movements_created_by_user_id",
        ),
        # Restricción de chequeo: el monto del movimiento debe ser estrictamente mayor a 0
        sa.CheckConstraint("amount_mxn > 0", name="chk_cash_movements_amount_positive"),
        schema=SCHEMA,
    )

    # Creación de índices optimizados para cash_movements
    op.create_index(
        "idx_cash_movements_tenant_shift",
        "cash_movements",
        ["tenant_id", "shift_id"],
        schema=SCHEMA,
    )
    op.create_index(
        "idx_cash_movements_tenant_created",
        "cash_movements",
        ["tenant_id", "created_at"],
        schema=SCHEMA,
    )

    # -------------------------------------------------------------------------
    # 4. Políticas de Seguridad a Nivel de Fila (Row Level Security - RLS)
    # -------------------------------------------------------------------------
    
    # Habilitar y forzar RLS en cash_shifts
    op.execute(f"ALTER TABLE {SCHEMA}.cash_shifts ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.cash_shifts FORCE ROW LEVEL SECURITY;")
    op.execute(
        f"CREATE POLICY tenant_isolation_cash_shifts ON {SCHEMA}.cash_shifts "
        f"FOR ALL USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);"
    )

    # Habilitar y forzar RLS en cash_movements
    op.execute(f"ALTER TABLE {SCHEMA}.cash_movements ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.cash_movements FORCE ROW LEVEL SECURITY;")
    op.execute(
        f"CREATE POLICY tenant_isolation_cash_movements ON {SCHEMA}.cash_movements "
        f"FOR ALL USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);"
    )


def downgrade() -> None:
    # Eliminación de políticas RLS
    op.execute(f"DROP POLICY IF EXISTS tenant_isolation_cash_movements ON {SCHEMA}.cash_movements;")
    op.execute(f"ALTER TABLE {SCHEMA}.cash_movements DISABLE ROW LEVEL SECURITY;")
    op.execute(f"DROP POLICY IF EXISTS tenant_isolation_cash_shifts ON {SCHEMA}.cash_shifts;")
    op.execute(f"ALTER TABLE {SCHEMA}.cash_shifts DISABLE ROW LEVEL SECURITY;")

    # Eliminación de tablas
    op.drop_table("cash_movements", schema=SCHEMA)
    op.drop_table("cash_shifts", schema=SCHEMA)

    # Eliminación de tipos ENUM de PostgreSQL
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.cash_movement_type_enum;")
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.shift_status_enum;")
