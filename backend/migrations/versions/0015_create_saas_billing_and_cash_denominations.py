"""Create saas billing and cash denominations tables

Revision ID: 0015_saas_billing_cash_denoms
Revises: 0014_add_supplier_id_to_products
Create Date: 2026-09-16 20:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

# Identificadores de revisión de Alembic
revision: str = "0015_saas_billing_cash_denoms"
down_revision: Union[str, None] = "0014_add_supplier_id_to_products"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Esquema canónico universal de la base de datos
SCHEMA = "public"


def upgrade() -> None:
    # 1. Crear tipo enumerado para métodos de pago SaaS
    op.execute(
        f"""
        DO $$ BEGIN
            CREATE TYPE {SCHEMA}.saas_payment_method_enum AS ENUM ('SPEI', 'OXXO', 'CARD');
        EXCEPTION
            WHEN duplicate_object THEN null;
        END $$;
        """
    )

    # 2. Crear tipo enumerado para estado de facturas SaaS
    op.execute(
        f"""
        DO $$ BEGIN
            CREATE TYPE {SCHEMA}.subscription_invoice_status_enum AS ENUM ('PENDING', 'PAID', 'OVERDUE', 'CANCELLED');
        EXCEPTION
            WHEN duplicate_object THEN null;
        END $$;
        """
    )

    # 3. Crear tabla de facturas de suscripción SaaS
    op.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.subscription_invoices (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            plan {SCHEMA}.tenant_plan_enum NOT NULL,
            amount_mxn NUMERIC(12, 2) NOT NULL,
            payment_method {SCHEMA}.saas_payment_method_enum NOT NULL DEFAULT 'SPEI',
            status {SCHEMA}.subscription_invoice_status_enum NOT NULL DEFAULT 'PENDING',
            period_start DATE NOT NULL,
            period_end DATE NOT NULL,
            payment_reference VARCHAR(64),
            clabe VARCHAR(18),
            oxxo_reference VARCHAR(20),
            paid_at TIMESTAMP WITH TIME ZONE,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT clock_timestamp(),
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT clock_timestamp()
        );
        """
    )

    # 4. Habilitar y forzar Row-Level Security en subscription_invoices
    op.execute(f"ALTER TABLE {SCHEMA}.subscription_invoices ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.subscription_invoices FORCE ROW LEVEL SECURITY;")
    op.execute(
        f"""
        DO $$ BEGIN
            DROP POLICY IF EXISTS subscription_invoices_tenant_isolation ON {SCHEMA}.subscription_invoices;
            CREATE POLICY subscription_invoices_tenant_isolation ON {SCHEMA}.subscription_invoices
                FOR ALL
                USING (
                    current_setting('app.bypass_rls', true) = 'on'
                    OR tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
                )
                WITH CHECK (
                    current_setting('app.bypass_rls', true) = 'on'
                    OR tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
                );
        EXCEPTION
            WHEN duplicate_object THEN null;
        END $$;
        """
    )

    # 5. Crear tabla de bitácora de webhooks de pasarelas de pago
    op.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.saas_webhook_logs (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            provider VARCHAR(32) NOT NULL,
            reference_id VARCHAR(64) NOT NULL,
            payload JSONB NOT NULL,
            processed BOOLEAN NOT NULL DEFAULT false,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT clock_timestamp()
        );
        """
    )
    op.execute(
        f"""
        CREATE INDEX IF NOT EXISTS idx_saas_webhook_logs_ref 
        ON {SCHEMA}.saas_webhook_logs(reference_id);
        """
    )

    # 6. Crear tabla de desglose de denominaciones físicas Banxico
    op.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.cash_session_denominations (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            shift_id UUID NOT NULL REFERENCES {SCHEMA}.cash_shifts(id) ON DELETE CASCADE,
            tenant_id UUID NOT NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            is_opening BOOLEAN NOT NULL DEFAULT true,
            bills_1000 INTEGER NOT NULL DEFAULT 0,
            bills_500 INTEGER NOT NULL DEFAULT 0,
            bills_200 INTEGER NOT NULL DEFAULT 0,
            bills_100 INTEGER NOT NULL DEFAULT 0,
            bills_50 INTEGER NOT NULL DEFAULT 0,
            bills_20 INTEGER NOT NULL DEFAULT 0,
            coins_20 INTEGER NOT NULL DEFAULT 0,
            coins_10 INTEGER NOT NULL DEFAULT 0,
            coins_5 INTEGER NOT NULL DEFAULT 0,
            coins_2 INTEGER NOT NULL DEFAULT 0,
            coins_1 INTEGER NOT NULL DEFAULT 0,
            coins_050 INTEGER NOT NULL DEFAULT 0,
            total_calculated_mxn NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT clock_timestamp()
        );
        """
    )

    # 7. Habilitar y forzar Row-Level Security en cash_session_denominations
    op.execute(f"ALTER TABLE {SCHEMA}.cash_session_denominations ENABLE ROW LEVEL SECURITY;")
    op.execute(f"ALTER TABLE {SCHEMA}.cash_session_denominations FORCE ROW LEVEL SECURITY;")
    op.execute(
        f"""
        DO $$ BEGIN
            DROP POLICY IF EXISTS cash_session_denominations_tenant_isolation ON {SCHEMA}.cash_session_denominations;
            CREATE POLICY cash_session_denominations_tenant_isolation ON {SCHEMA}.cash_session_denominations
                FOR ALL
                USING (
                    current_setting('app.bypass_rls', true) = 'on'
                    OR tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
                )
                WITH CHECK (
                    current_setting('app.bypass_rls', true) = 'on'
                    OR tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
                );
        EXCEPTION
            WHEN duplicate_object THEN null;
        END $$;
        """
    )


def downgrade() -> None:
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.cash_session_denominations CASCADE;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.saas_webhook_logs CASCADE;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.subscription_invoices CASCADE;")
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.subscription_invoice_status_enum;")
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.saas_payment_method_enum;")
