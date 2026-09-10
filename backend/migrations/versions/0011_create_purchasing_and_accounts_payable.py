"""Create suppliers, purchase_orders, purchase_order_items, accounts_payable and supplier_payment_ledger tables with RLS and enum types

Revision ID: 0011_purchases_and_cxp
Revises: 0010_customers_and_credit_ledger
Create Date: 2026-09-10 12:00:00.000000

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
revision: str = "0011_purchases_and_cxp"
# Identificador de la revisión previa (0010_customers_and_credit_ledger)
down_revision: Union[str, None] = "0010_customers_and_credit_ledger"
# Etiquetas de ramificación
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias cruzadas
depends_on: Union[str, Sequence[str], None] = None

# Nombre del esquema de base de datos
SCHEMA = "inventmx"


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. Creación de Tipos ENUM de PostgreSQL para Compras y Cuentas por Pagar
    # -------------------------------------------------------------------------
    
    # Enum de estado de proveedor (ACTIVE, INACTIVE)
    supplier_status_enum = postgresql.ENUM(
        "ACTIVE",
        "INACTIVE",
        name="supplier_status_enum",
        schema=SCHEMA,
        create_type=False,
    )
    op.execute(
        f"""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE t.typname = 'supplier_status_enum' AND n.nspname = '{SCHEMA}') THEN
                CREATE TYPE {SCHEMA}.supplier_status_enum AS ENUM ('ACTIVE', 'INACTIVE');
            END IF;
        END$$;
        """
    )

    # Enum de estado de orden de compra
    purchase_order_status_enum = postgresql.ENUM(
        "DRAFT",
        "SENT",
        "CONFIRMED",
        "PARTIALLY_RECEIVED",
        "RECEIVED",
        "CANCELLED",
        name="purchase_order_status_enum",
        schema=SCHEMA,
        create_type=False,
    )
    op.execute(
        f"""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE t.typname = 'purchase_order_status_enum' AND n.nspname = '{SCHEMA}') THEN
                CREATE TYPE {SCHEMA}.purchase_order_status_enum AS ENUM ('DRAFT', 'SENT', 'CONFIRMED', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CANCELLED');
            END IF;
        END$$;
        """
    )

    # Enum de estado de cuenta por pagar (CxP)
    account_payable_status_enum = postgresql.ENUM(
        "PENDING",
        "PARTIALLY_PAID",
        "PAID",
        "OVERDUE",
        "CANCELLED",
        name="account_payable_status_enum",
        schema=SCHEMA,
        create_type=False,
    )
    op.execute(
        f"""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE t.typname = 'account_payable_status_enum' AND n.nspname = '{SCHEMA}') THEN
                CREATE TYPE {SCHEMA}.account_payable_status_enum AS ENUM ('PENDING', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'CANCELLED');
            END IF;
        END$$;
        """
    )

    # -------------------------------------------------------------------------
    # 2. Creación de Tabla inventmx.suppliers (Proveedores)
    # -------------------------------------------------------------------------
    op.create_table(
        "suppliers",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(150), nullable=False),
        sa.Column("rfc", sa.String(13), nullable=True),
        sa.Column("phone", sa.String(30), nullable=True),
        sa.Column("email", sa.String(100), nullable=True),
        sa.Column("address", sa.Text(), nullable=True),
        sa.Column("credit_days", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("credit_limit_mxn", sa.Numeric(14, 2), nullable=False, server_default="0.00"),
        sa.Column("status", supplier_status_enum, nullable=False, server_default="ACTIVE"),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("credit_days >= 0", name="chk_suppliers_credit_days"),
        sa.CheckConstraint("credit_limit_mxn >= 0", name="chk_suppliers_credit_limit_mxn"),
        schema=SCHEMA,
    )
    op.create_index("idx_suppliers_tenant_name", "suppliers", ["tenant_id", "name"], schema=SCHEMA)
    op.create_index("idx_suppliers_tenant_rfc", "suppliers", ["tenant_id", "rfc"], schema=SCHEMA)

    # -------------------------------------------------------------------------
    # 3. Creación de Tabla inventmx.purchase_orders (Órdenes de Compra)
    # -------------------------------------------------------------------------
    op.create_table(
        "purchase_orders",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("supplier_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.suppliers.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("warehouse_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.warehouses.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("folio", sa.String(50), nullable=False),
        sa.Column("status", purchase_order_status_enum, nullable=False, server_default="DRAFT"),
        sa.Column("subtotal_mxn", sa.Numeric(14, 2), nullable=False, server_default="0.00"),
        sa.Column("tax_mxn", sa.Numeric(14, 2), nullable=False, server_default="0.00"),
        sa.Column("total_mxn", sa.Numeric(14, 2), nullable=False, server_default="0.00"),
        sa.Column("expected_delivery_date", sa.Date(), nullable=True),
        sa.Column("received_date", sa.Date(), nullable=True),
        sa.Column("invoice_reference", sa.String(100), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_by_user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.users.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("subtotal_mxn >= 0", name="chk_purchase_orders_subtotal_mxn"),
        sa.CheckConstraint("tax_mxn >= 0", name="chk_purchase_orders_tax_mxn"),
        sa.CheckConstraint("total_mxn >= 0", name="chk_purchase_orders_total_mxn"),
        sa.UniqueConstraint("tenant_id", "folio", name="uq_purchase_orders_tenant_folio"),
        schema=SCHEMA,
    )
    op.create_index("idx_purchase_orders_tenant_supplier", "purchase_orders", ["tenant_id", "supplier_id"], schema=SCHEMA)
    op.create_index("idx_purchase_orders_tenant_status", "purchase_orders", ["tenant_id", "status"], schema=SCHEMA)
    op.create_index("idx_purchase_orders_tenant_created_at", "purchase_orders", ["tenant_id", "created_at"], schema=SCHEMA)

    # -------------------------------------------------------------------------
    # 4. Creación de Tabla inventmx.purchase_order_items (Ítems de la Orden)
    # -------------------------------------------------------------------------
    op.create_table(
        "purchase_order_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("purchase_order_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.purchase_orders.id", ondelete="CASCADE"), nullable=False),
        sa.Column("product_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.products.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("quantity_ordered", sa.Numeric(14, 4), nullable=False),
        sa.Column("quantity_received", sa.Numeric(14, 4), nullable=False, server_default="0.0000"),
        sa.Column("unit_cost_mxn", sa.Numeric(14, 4), nullable=False, server_default="0.0000"),
        sa.Column("subtotal_mxn", sa.Numeric(14, 2), nullable=False, server_default="0.00"),
        sa.Column("lot_number", sa.String(50), nullable=True),
        sa.Column("expiry_date", sa.Date(), nullable=True),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("quantity_ordered > 0", name="chk_po_items_quantity_ordered"),
        sa.CheckConstraint("quantity_received >= 0", name="chk_po_items_quantity_received"),
        sa.CheckConstraint("unit_cost_mxn >= 0", name="chk_po_items_unit_cost_mxn"),
        sa.CheckConstraint("subtotal_mxn >= 0", name="chk_po_items_subtotal_mxn"),
        schema=SCHEMA,
    )
    op.create_index("idx_po_items_tenant_order", "purchase_order_items", ["tenant_id", "purchase_order_id"], schema=SCHEMA)
    op.create_index("idx_po_items_tenant_product", "purchase_order_items", ["tenant_id", "product_id"], schema=SCHEMA)

    # -------------------------------------------------------------------------
    # 5. Creación de Tabla inventmx.accounts_payable (Cuentas por Pagar CxP)
    # -------------------------------------------------------------------------
    op.create_table(
        "accounts_payable",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("supplier_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.suppliers.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("purchase_order_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.purchase_orders.id", ondelete="SET NULL"), nullable=True),
        sa.Column("folio", sa.String(50), nullable=False),
        sa.Column("total_mxn", sa.Numeric(14, 2), nullable=False),
        sa.Column("amount_paid_mxn", sa.Numeric(14, 2), nullable=False, server_default="0.00"),
        sa.Column("status", account_payable_status_enum, nullable=False, server_default="PENDING"),
        sa.Column("due_date", sa.Date(), nullable=False),
        sa.Column("invoice_reference", sa.String(100), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("total_mxn >= 0", name="chk_accounts_payable_total_mxn"),
        sa.CheckConstraint("amount_paid_mxn >= 0", name="chk_accounts_payable_amount_paid_mxn"),
        sa.UniqueConstraint("tenant_id", "folio", name="uq_accounts_payable_tenant_folio"),
        schema=SCHEMA,
    )
    op.create_index("idx_ap_tenant_supplier", "accounts_payable", ["tenant_id", "supplier_id"], schema=SCHEMA)
    op.create_index("idx_ap_tenant_status", "accounts_payable", ["tenant_id", "status"], schema=SCHEMA)
    op.create_index("idx_ap_tenant_due_date", "accounts_payable", ["tenant_id", "due_date"], schema=SCHEMA)

    # -------------------------------------------------------------------------
    # 6. Creación de Tabla inventmx.supplier_payment_ledger (Abonos a Proveedores)
    # -------------------------------------------------------------------------
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
        "supplier_payment_ledger",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("account_payable_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.accounts_payable.id", ondelete="CASCADE"), nullable=False),
        sa.Column("supplier_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.suppliers.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("amount_paid_mxn", sa.Numeric(14, 2), nullable=False),
        sa.Column("payment_method", payment_method_enum, nullable=False, server_default="CASH_MXN"),
        sa.Column("reference_code", sa.String(100), nullable=True),
        sa.Column("payment_date", sa.Date(), nullable=False, server_default=sa.func.current_date()),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_by_user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey(f"{SCHEMA}.users.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("amount_paid_mxn > 0", name="chk_supplier_payment_amount_mxn"),
        schema=SCHEMA,
    )
    op.create_index("idx_supplier_payment_tenant_ap", "supplier_payment_ledger", ["tenant_id", "account_payable_id"], schema=SCHEMA)
    op.create_index("idx_supplier_payment_tenant_supplier", "supplier_payment_ledger", ["tenant_id", "supplier_id"], schema=SCHEMA)

    # -------------------------------------------------------------------------
    # 7. Habilitación de Row-Level Security (RLS) y Políticas de Aislamiento
    # -------------------------------------------------------------------------
    tables_to_secure = [
        "suppliers",
        "purchase_orders",
        "purchase_order_items",
        "accounts_payable",
        "supplier_payment_ledger",
    ]

    for tbl in tables_to_secure:
        op.execute(f"ALTER TABLE {SCHEMA}.{tbl} ENABLE ROW LEVEL SECURITY;")
        op.execute(
            f"""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_policies 
                    WHERE schemaname = '{SCHEMA}' 
                    AND tablename = '{tbl}' 
                    AND policyname = 'tenant_isolation_policy'
                ) THEN
                    CREATE POLICY tenant_isolation_policy ON {SCHEMA}.{tbl}
                    FOR ALL
                    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
                END IF;
            END$$;
            """
        )


def downgrade() -> None:
    # -------------------------------------------------------------------------
    # Reversión de Políticas RLS y Tablas
    # -------------------------------------------------------------------------
    tables_to_drop = [
        "supplier_payment_ledger",
        "accounts_payable",
        "purchase_order_items",
        "purchase_orders",
        "suppliers",
    ]

    for tbl in tables_to_drop:
        op.execute(f"DROP POLICY IF EXISTS tenant_isolation_policy ON {SCHEMA}.{tbl};")
        op.drop_table(tbl, schema=SCHEMA)

    # Eliminación de tipos ENUM creados
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.account_payable_status_enum;")
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.purchase_order_status_enum;")
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.supplier_status_enum;")
