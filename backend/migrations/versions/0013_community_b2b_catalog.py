"""Create b2b_listings, b2b_orders, and b2b_order_items tables with RLS and enums

Revision ID: 0013_community_b2b_catalog
Revises: 0012_public_digital_catalog
Create Date: 2026-09-13 14:30:00.000000

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
revision: str = "0013_community_b2b_catalog"
# Identificador de la revisión previa (0012_public_digital_catalog)
down_revision: Union[str, None] = "0012_public_digital_catalog"
# Etiquetas de ramificación
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias cruzadas
depends_on: Union[str, Sequence[str], None] = None

# Nombre del esquema de base de datos
SCHEMA = "public"


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. Creación de Tipos ENUM de PostgreSQL para B2B Marketplace
    # -------------------------------------------------------------------------
    op.execute(
        f"""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE t.typname = 'b2b_order_status_enum' AND n.nspname = '{SCHEMA}') THEN
                CREATE TYPE {SCHEMA}.b2b_order_status_enum AS ENUM ('PENDING', 'ACCEPTED', 'REJECTED', 'COMPLETED', 'CANCELLED');
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE t.typname = 'b2b_delivery_type_enum' AND n.nspname = '{SCHEMA}') THEN
                CREATE TYPE {SCHEMA}.b2b_delivery_type_enum AS ENUM ('PICKUP', 'DELIVERY');
            END IF;
        END$$;
        """
    )

    # -------------------------------------------------------------------------
    # 2. Creación de Tabla 'b2b_listings' para ofertas mayoristas comunitarias
    # -------------------------------------------------------------------------
    op.create_table(
        "b2b_listings",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
            comment="Identificador único universal de la publicación B2B",
        ),
        sa.Column(
            "tenant_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
            comment="Comercio vendedor que publica la oferta",
        ),
        sa.Column(
            "product_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey(f"{SCHEMA}.products.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
            comment="Producto base publicado en la red mayorista",
        ),
        sa.Column(
            "product_name",
            sa.String(255),
            nullable=False,
            server_default="Producto B2B",
            comment="Nombre instantáneo del producto publicado para búsqueda federada",
        ),
        sa.Column(
            "product_sku",
            sa.String(100),
            nullable=True,
            comment="Código SKU o de barras del producto mayorista",
        ),
        sa.Column(
            "product_image_url",
            sa.Text(),
            nullable=True,
            comment="URL de imagen del producto",
        ),
        sa.Column(
            "wholesale_price_mxn",
            sa.Numeric(12, 2),
            nullable=False,
            comment="Precio de mayoreo por unidad en Pesos Mexicanos ($ MXN)",
        ),
        sa.Column(
            "regular_price_mxn",
            sa.Numeric(12, 2),
            nullable=True,
            comment="Precio regular de venta al público en $ MXN como referencia",
        ),
        sa.Column(
            "min_wholesale_quantity",
            sa.Numeric(10, 2),
            nullable=False,
            server_default=sa.text("1.00"),
            comment="Cantidad mínima de compra para acceder al precio de mayoreo",
        ),
        sa.Column(
            "available_b2b_stock",
            sa.Numeric(10, 2),
            nullable=False,
            server_default=sa.text("0.00"),
            comment="Existencias físicas destinadas a venta mayorista B2B",
        ),
        sa.Column(
            "location_postal_code",
            sa.String(10),
            nullable=True,
            index=True,
            comment="Código postal de ubicación de la tienda para filtrado por cercanía",
        ),
        sa.Column(
            "location_city",
            sa.String(100),
            nullable=True,
            index=True,
            comment="Ciudad o municipio de la tienda",
        ),
        sa.Column(
            "is_active",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
            comment="Indica si la oferta está activa y visible en el marketplace comunitario",
        ),
        sa.Column(
            "notes",
            sa.Text(),
            nullable=True,
            comment="Condiciones comerciales especiales o notas de entrega",
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
            comment="Fecha de publicación de la oferta",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
            nullable=False,
            comment="Fecha de última actualización",
        ),
        sa.CheckConstraint("wholesale_price_mxn >= 0", name="chk_b2b_wholesale_price_non_negative"),
        sa.CheckConstraint("min_wholesale_quantity > 0", name="chk_b2b_min_wholesale_qty_positive"),
        sa.CheckConstraint("available_b2b_stock >= 0", name="chk_b2b_stock_non_negative"),
        schema=SCHEMA,
    )

    # -------------------------------------------------------------------------
    # 3. Creación de Tabla 'b2b_orders' para transacciones entre comercios
    # -------------------------------------------------------------------------
    op.create_table(
        "b2b_orders",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
            comment="Identificador único del pedido B2B",
        ),
        sa.Column(
            "order_number",
            sa.String(50),
            unique=True,
            nullable=False,
            index=True,
            comment="Folio único del pedido mayorista (ej: B2B-2026-0001)",
        ),
        sa.Column(
            "buyer_tenant_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
            comment="Comercio comprador",
        ),
        sa.Column(
            "seller_tenant_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
            comment="Comercio vendedor",
        ),
        sa.Column(
            "status",
            postgresql.ENUM(
                "PENDING", "ACCEPTED", "REJECTED", "COMPLETED", "CANCELLED",
                name="b2b_order_status_enum",
                schema=SCHEMA,
                create_type=False,
            ),
            nullable=False,
            server_default="PENDING",
            index=True,
            comment="Estado transaccional del pedido B2B",
        ),
        sa.Column(
            "total_mxn",
            sa.Numeric(12, 2),
            nullable=False,
            server_default=sa.text("0.00"),
            comment="Importe total del pedido en Pesos Mexicanos ($ MXN)",
        ),
        sa.Column(
            "delivery_type",
            postgresql.ENUM(
                "PICKUP", "DELIVERY",
                name="b2b_delivery_type_enum",
                schema=SCHEMA,
                create_type=False,
            ),
            nullable=False,
            server_default="PICKUP",
            comment="Modalidad de entrega",
        ),
        sa.Column(
            "delivery_address",
            sa.Text(),
            nullable=True,
            comment="Dirección pactada si es entrega a domicilio",
        ),
        sa.Column(
            "notes",
            sa.Text(),
            nullable=True,
            comment="Notas y acuerdos comerciales",
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
            comment="Fecha de emisión del pedido",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
            nullable=False,
            comment="Fecha de actualización del pedido",
        ),
        sa.CheckConstraint("total_mxn >= 0", name="chk_b2b_order_total_non_negative"),
        schema=SCHEMA,
    )

    # -------------------------------------------------------------------------
    # 4. Creación de Tabla 'b2b_order_items' para renglones del pedido
    # -------------------------------------------------------------------------
    op.create_table(
        "b2b_order_items",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
            comment="Identificador único del renglón de pedido B2B",
        ),
        sa.Column(
            "b2b_order_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey(f"{SCHEMA}.b2b_orders.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
            comment="Clave foránea hacia el pedido B2B",
        ),
        sa.Column(
            "b2b_listing_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey(f"{SCHEMA}.b2b_listings.id", ondelete="RESTRICT"),
            nullable=False,
            index=True,
            comment="Publicación B2B de origen",
        ),
        sa.Column(
            "product_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey(f"{SCHEMA}.products.id", ondelete="RESTRICT"),
            nullable=False,
            comment="Producto físico del vendedor",
        ),
        sa.Column(
            "product_name",
            sa.String(255),
            nullable=False,
            comment="Nombre congelado del producto al momento de solicitar",
        ),
        sa.Column(
            "quantity",
            sa.Numeric(10, 2),
            nullable=False,
            comment="Cantidad de piezas solicitadas",
        ),
        sa.Column(
            "unit_price_mxn",
            sa.Numeric(12, 2),
            nullable=False,
            comment="Precio unitario mayorista pactado en $ MXN",
        ),
        sa.Column(
            "subtotal_mxn",
            sa.Numeric(12, 2),
            nullable=False,
            comment="Subtotal de la partida en Pesos Mexicanos ($ MXN)",
        ),
        sa.CheckConstraint("quantity > 0", name="chk_b2b_order_item_qty_positive"),
        sa.CheckConstraint("unit_price_mxn >= 0", name="chk_b2b_order_item_price_non_negative"),
        sa.CheckConstraint("subtotal_mxn >= 0", name="chk_b2b_order_item_subtotal_non_negative"),
        schema=SCHEMA,
    )

    # -------------------------------------------------------------------------
    # 5. Índices de Búsqueda y Rendimiento
    # -------------------------------------------------------------------------
    op.create_index(
        "ix_b2b_listings_marketplace",
        "b2b_listings",
        ["is_active", "wholesale_price_mxn", "location_city"],
        schema=SCHEMA,
    )


def downgrade() -> None:
    # 1. Eliminar índices
    op.drop_index("ix_b2b_listings_marketplace", table_name="b2b_listings", schema=SCHEMA)

    # 2. Eliminar tablas
    op.drop_table("b2b_order_items", schema=SCHEMA)
    op.drop_table("b2b_orders", schema=SCHEMA)
    op.drop_table("b2b_listings", schema=SCHEMA)

    # 3. Eliminar tipos enum
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.b2b_delivery_type_enum;")
    op.execute(f"DROP TYPE IF EXISTS {SCHEMA}.b2b_order_status_enum;")
