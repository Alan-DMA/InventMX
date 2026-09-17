"""Create catalog_settings table, show_in_catalog column in products, and RLS policies

Revision ID: 0012_public_digital_catalog
Revises: 0011_purchases_and_cxp
Create Date: 2026-09-13 14:00:00.000000

"""
# Importación de tipos para anotación de dependencias de Alembic
from typing import Sequence, Union
# Importación de operaciones de esquema de Alembic
from alembic import op
# Importación de SQLAlchemy
import sqlalchemy as sa
# Importación de dialecto PostgreSQL para tipos específicos (UUID)
from sqlalchemy.dialects import postgresql

# Identificador de la revisión actual
revision: str = "0012_public_digital_catalog"
# Identificador de la revisión previa (0011_purchases_and_cxp)
down_revision: Union[str, None] = "0011_purchases_and_cxp"
# Etiquetas de ramificación
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias cruzadas
depends_on: Union[str, Sequence[str], None] = None

# Nombre del esquema de base de datos
SCHEMA = "public"


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. Agregar columna 'show_in_catalog' en tabla 'products'
    # -------------------------------------------------------------------------
    op.add_column(
        "products",
        sa.Column(
            "show_in_catalog",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
            comment="Indica si el producto se muestra en el catálogo público de WhatsApp",
        ),
        schema=SCHEMA,
    )

    # -------------------------------------------------------------------------
    # 2. Creación de Tabla 'catalog_settings' para configuración del Catálogo Web
    # -------------------------------------------------------------------------
    op.create_table(
        "catalog_settings",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
            comment="Identificador único universal de la configuración de catálogo",
        ),
        sa.Column(
            "tenant_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
            comment="Clave foránea única hacia el comercio dueño de la configuración",
        ),
        sa.Column(
            "is_catalog_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
            comment="Bandera maestra que habilita o suspende el catálogo web público",
        ),
        sa.Column(
            "whatsapp_number",
            sa.String(20),
            nullable=True,
            comment="Número de WhatsApp en formato E.164 (ej: 5215512345678) para recibir pedidos",
        ),
        sa.Column(
            "welcome_message",
            sa.Text(),
            nullable=True,
            comment="Mensaje de bienvenida personalizado que se muestra en el catálogo web",
        ),
        sa.Column(
            "min_order_amount_mxn",
            sa.Numeric(12, 2),
            nullable=False,
            server_default=sa.text("0.00"),
            comment="Monto mínimo de compra requerido para procesar el pedido en $ MXN",
        ),
        sa.Column(
            "delivery_fee_mxn",
            sa.Numeric(12, 2),
            nullable=False,
            server_default=sa.text("0.00"),
            comment="Costo de envío a domicilio en Pesos Mexicanos ($ MXN)",
        ),
        sa.Column(
            "delivery_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
            comment="Indica si el comercio ofrece servicio de entrega a domicilio",
        ),
        sa.Column(
            "pickup_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
            comment="Indica si el comercio permite recoger pedidos en sucursal",
        ),
        sa.Column(
            "business_hours",
            sa.Text(),
            nullable=True,
            comment="Horario de atención al público y recepción de pedidos",
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
            comment="Fecha y hora de creación de la configuración",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
            nullable=False,
            comment="Fecha y hora de última modificación",
        ),
        sa.CheckConstraint(
            "min_order_amount_mxn >= 0",
            name="chk_catalog_min_order_mxn_non_negative",
        ),
        sa.CheckConstraint(
            "delivery_fee_mxn >= 0",
            name="chk_catalog_delivery_fee_mxn_non_negative",
        ),
        schema=SCHEMA,
    )

    # -------------------------------------------------------------------------
    # 3. Índices de rendimiento
    # -------------------------------------------------------------------------
    op.create_index(
        "ix_catalog_settings_tenant_id",
        "catalog_settings",
        ["tenant_id"],
        unique=True,
        schema=SCHEMA,
    )
    op.create_index(
        "ix_products_show_in_catalog",
        "products",
        ["tenant_id", "show_in_catalog", "is_active"],
        schema=SCHEMA,
    )

    # -------------------------------------------------------------------------
    # 4. Habilitar Row Level Security (RLS) y Políticas Multi-tenant
    # -------------------------------------------------------------------------
    op.execute(f"ALTER TABLE {SCHEMA}.catalog_settings ENABLE ROW LEVEL SECURITY;")
    op.execute(
        f"""
        CREATE POLICY tenant_isolation_catalog_settings ON {SCHEMA}.catalog_settings
        FOR ALL
        USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid);
        """
    )


def downgrade() -> None:
    # 1. Eliminar políticas RLS
    op.execute(f"DROP POLICY IF EXISTS tenant_isolation_catalog_settings ON {SCHEMA}.catalog_settings;")
    op.execute(f"ALTER TABLE {SCHEMA}.catalog_settings DISABLE ROW LEVEL SECURITY;")

    # 2. Eliminar índices
    op.drop_index("ix_products_show_in_catalog", table_name="products", schema=SCHEMA)
    op.drop_index("ix_catalog_settings_tenant_id", table_name="catalog_settings", schema=SCHEMA)

    # 3. Eliminar tabla catalog_settings
    op.drop_table("catalog_settings", schema=SCHEMA)

    # 4. Eliminar columna show_in_catalog de products
    op.drop_column("products", "show_in_catalog", schema=SCHEMA)
