"""Create customers and customer_credit_ledger tables with RLS and enum types

Revision ID: 0010_customers_and_credit_ledger
Revises: 0009_cash_shifts_and_movements
Create Date: 2026-09-10 11:00:00.000000

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
revision: str = "0010_customers_and_credit_ledger"
# Identificador de la revisión previa (0009_cash_shifts_and_movements)
down_revision: Union[str, None] = "0009_cash_shifts_and_movements"
# Etiquetas de ramificación
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias cruzadas
depends_on: Union[str, Sequence[str], None] = None

# Nombre del esquema de base de datos
SCHEMA = "inventmx"


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. Creación de Tipos ENUM de PostgreSQL para Libro Mayor de Crédito
    # -------------------------------------------------------------------------
    
    # Declaración del tipo enum para el tipo de asiento (CHARGE = Cargo por venta, PAYMENT = Abono/Pago, ADJUSTMENT = Ajuste manual)
    ledger_entry_type_enum = postgresql.ENUM(
        "CHARGE",
        "PAYMENT",
        "ADJUSTMENT",
        name="ledger_entry_type_enum",
        schema=SCHEMA,
        create_type=False,
    )
    # Creación idempotente en PostgreSQL
    op.execute(
        f"DO $$ BEGIN "
        f"  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE t.typname = 'ledger_entry_type_enum' AND n.nspname = '{SCHEMA}') THEN "
        f"    CREATE TYPE {SCHEMA}.ledger_entry_type_enum AS ENUM ('CHARGE', 'PAYMENT', 'ADJUSTMENT'); "
        f"  END IF; "
        f"END $$;"
    )

    # -------------------------------------------------------------------------
    # 2. Creación de la Tabla de Clientes (inventmx.customers)
    # -------------------------------------------------------------------------
    op.create_table(
        "customers",
        # Identificador único universal del cliente
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        # Identificador del inquilino propietario para aislamiento multi-tenant
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        # Nombre completo o razón social del cliente
        sa.Column("full_name", sa.String(150), nullable=False),
        # Teléfono de contacto o WhatsApp
        sa.Column("phone", sa.String(30), nullable=True),
        # Correo electrónico
        sa.Column("email", sa.String(100), nullable=True),
        # Domicilio físico del cliente
        sa.Column("address", sa.Text(), nullable=True),
        # Registro Federal de Contribuyentes (RFC) opcional
        sa.Column("rfc", sa.String(13), nullable=True),
        # Límite máximo de crédito otorgado en Pesos Mexicanos ($ MXN)
        sa.Column("credit_limit_mxn", sa.Numeric(12, 2), nullable=False, server_default="0.00"),
        # Saldo deudor acumulado actual en Pesos Mexicanos ($ MXN)
        sa.Column("credit_balance_mxn", sa.Numeric(12, 2), nullable=False, server_default="0.00"),
        # Plazo de crédito concedido en días
        sa.Column("credit_days", sa.Integer(), nullable=False, server_default="0"),
        # Estado activo/inactivo del cliente
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        # Observaciones y notas crediticias
        sa.Column("notes", sa.Text(), nullable=True),
        # Marca de tiempo de creación
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        # Marca de tiempo de última actualización
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now(), onupdate=sa.func.now()),
        # Restricción de clave foránea a tenants con borrado en cascada
        sa.ForeignKeyConstraint(
            ["tenant_id"],
            [f"{SCHEMA}.tenants.id"],
            ondelete="CASCADE",
            name="fk_customers_tenant_id",
        ),
        # Chequeos de validación financiera
        sa.CheckConstraint("credit_limit_mxn >= 0", name="chk_customers_credit_limit_non_negative"),
        sa.CheckConstraint("credit_balance_mxn >= 0", name="chk_customers_credit_balance_non_negative"),
        sa.CheckConstraint("credit_days >= 0", name="chk_customers_credit_days_non_negative"),
        schema=SCHEMA,
    )

    # Creación de índices de alto desempeño para customers
    op.create_index("idx_customers_tenant_name", "customers", ["tenant_id", "full_name"], schema=SCHEMA)
    op.create_index("idx_customers_tenant_phone", "customers", ["tenant_id", "phone"], schema=SCHEMA)
    op.create_index("idx_customers_tenant_rfc", "customers", ["tenant_id", "rfc"], schema=SCHEMA)
    op.create_index("idx_customers_tenant_created", "customers", ["tenant_id", "created_at"], schema=SCHEMA)

    # -------------------------------------------------------------------------
    # 3. Creación de la Tabla de Libro Mayor de Crédito (inventmx.customer_credit_ledger)
    # -------------------------------------------------------------------------
    
    # Declaración del tipo enum payment_method_enum existente para los abonos
    payment_method_enum = postgresql.ENUM(
        "CASH_MXN",
        "SPEI",
        "CODI",
        "CARD_TPV",
        "OTHER",
        name="payment_method_enum",
        schema=SCHEMA,
        create_type=False,
    )

    op.create_table(
        "customer_credit_ledger",
        # Identificador único del asiento de crédito
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        # Identificador del inquilino propietario para aislamiento multi-tenant
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        # Identificador del cliente titular de la cuenta
        sa.Column("customer_id", postgresql.UUID(as_uuid=True), nullable=False),
        # Identificador de la venta asociada (opcional, en caso de cargo o liquidación de nota)
        sa.Column("sale_id", postgresql.UUID(as_uuid=True), nullable=True),
        # Tipo de asiento (CHARGE, PAYMENT, ADJUSTMENT)
        sa.Column("entry_type", ledger_entry_type_enum, nullable=False),
        # Monto de la transacción en Pesos Mexicanos (siempre positivo)
        sa.Column("amount_mxn", sa.Numeric(12, 2), nullable=False),
        # Saldo deudor anterior antes del movimiento
        sa.Column("previous_balance_mxn", sa.Numeric(12, 2), nullable=False),
        # Saldo deudor resultante después del movimiento
        sa.Column("resulting_balance_mxn", sa.Numeric(12, 2), nullable=False),
        # Método de pago utilizado para el abono (en caso de PAYMENT)
        sa.Column("payment_method", payment_method_enum, nullable=True),
        # Código de referencia o folio bancario (SPEI, voucher)
        sa.Column("reference_code", sa.String(100), nullable=True),
        # Observaciones o concepto del asiento
        sa.Column("notes", sa.Text(), nullable=True),
        # Usuario cajero o supervisor que registró el movimiento
        sa.Column("created_by_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        # Marca de tiempo de registro del asiento contable
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        # Restricción de clave foránea a tenants
        sa.ForeignKeyConstraint(
            ["tenant_id"],
            [f"{SCHEMA}.tenants.id"],
            ondelete="CASCADE",
            name="fk_credit_ledger_tenant_id",
        ),
        # Restricción de clave foránea a customers
        sa.ForeignKeyConstraint(
            ["customer_id"],
            [f"{SCHEMA}.customers.id"],
            ondelete="CASCADE",
            name="fk_credit_ledger_customer_id",
        ),
        # Restricción de clave foránea a sales (opcional)
        sa.ForeignKeyConstraint(
            ["sale_id"],
            [f"{SCHEMA}.sales.id"],
            ondelete="SET NULL",
            name="fk_credit_ledger_sale_id",
        ),
        # Restricción de clave foránea a users
        sa.ForeignKeyConstraint(
            ["created_by_user_id"],
            [f"{SCHEMA}.users.id"],
            ondelete="RESTRICT",
            name="fk_credit_ledger_created_by_user_id",
        ),
        # Restricción de chequeo: monto estrictamente mayor a 0
        sa.CheckConstraint("amount_mxn > 0", name="chk_credit_ledger_amount_positive"),
        sa.CheckConstraint("previous_balance_mxn >= 0", name="chk_credit_ledger_prev_balance_non_neg"),
        sa.CheckConstraint("resulting_balance_mxn >= 0", name="chk_credit_ledger_res_balance_non_neg"),
        schema=SCHEMA,
    )

    # Creación de índices de alto desempeño para credit_ledger
    op.create_index("idx_credit_ledger_tenant_customer", "customer_credit_ledger", ["tenant_id", "customer_id"], schema=SCHEMA)
    op.create_index("idx_credit_ledger_tenant_sale", "customer_credit_ledger", ["tenant_id", "sale_id"], schema=SCHEMA)
    op.create_index("idx_credit_ledger_tenant_created", "customer_credit_ledger", ["tenant_id", "created_at"], schema=SCHEMA)

    # -------------------------------------------------------------------------
    # 4. Políticas de Seguridad a Nivel de Fila (Row Level Security - RLS)
    # -------------------------------------------------------------------------
    
    # Habilitar y forzar RLS en customers
    op.execute(f"ALTER TABLE {SCHEMA}.customers ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.customers FORCE ROW LEVEL SECURITY;")
    op.execute(
        f"CREATE POLICY tenant_isolation_customers ON {SCHEMA}.customers "
        f"FOR ALL USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);"
    )

    # Habilitar y forzar RLS en customer_credit_ledger
    op.execute(f"ALTER TABLE {SCHEMA}.customer_credit_ledger ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.customer_credit_ledger FORCE ROW LEVEL SECURITY;")
    op.execute(
        f"CREATE POLICY tenant_isolation_customer_credit_ledger ON {SCHEMA}.customer_credit_ledger "
        f"FOR ALL USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);"
    )


def downgrade() -> None:
    # Eliminación de políticas RLS
    op.execute(f"DROP POLICY IF EXISTS tenant_isolation_customer_credit_ledger ON {SCHEMA}.customer_credit_ledger;")
    op.execute(f"ALTER TABLE {SCHEMA}.customer_credit_ledger DISABLE ROW LEVEL SECURITY;")
    op.execute(f"DROP POLICY IF EXISTS tenant_isolation_customers ON {SCHEMA}.customers;")
    op.execute(f"ALTER TABLE {SCHEMA}.customers DISABLE ROW LEVEL SECURITY;")

    # Eliminación de tablas
    op.drop_table("customer_credit_ledger", schema=SCHEMA)
    op.drop_table("customers", schema=SCHEMA)

    # Eliminación de tipo ENUM
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.ledger_entry_type_enum;")
