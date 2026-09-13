# Importación del módulo datetime para marcas temporales con zona horaria
from datetime import datetime
# Importación del módulo decimal para operaciones monetarias exactas
from decimal import Decimal
# Importación de tipado estático
from typing import Optional
# Importación de identificadores únicos universales UUID
import uuid
# Importación de constructs de SQLAlchemy
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa y esquema del sistema
from app.core.database.base import Base, SCHEMA


class B2BListing(Base):
    """
    Modelo de Dominio para una publicación mayorista comunitaria (RF-27 / Const. Art. 4.3).
    Permite a los comercios compartir lotes de productos a precio de mayoreo en $ MXN.
    """
    __tablename__ = "b2b_listings"
    __table_args__ = (
        CheckConstraint("wholesale_price_mxn >= 0", name="chk_b2b_wholesale_price_non_negative"),
        CheckConstraint("min_wholesale_quantity > 0", name="chk_b2b_min_wholesale_qty_positive"),
        CheckConstraint("available_b2b_stock >= 0", name="chk_b2b_stock_non_negative"),
        {"schema": SCHEMA},
    )

    # Identificador único UUID de la oferta
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único universal de la oferta mayorista",
    )

    # Identificador del comercio vendedor
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Comercio que pone a disposición la oferta mayorista",
    )

    # Identificador del producto físico en inventario
    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.products.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Producto base del inventario publicado en mayoreo",
    )

    # Nombre instantáneo del producto para búsqueda federada
    product_name: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        default="Producto B2B",
        doc="Nombre del producto mayorista",
    )

    # Código SKU del producto
    product_sku: Mapped[Optional[str]] = mapped_column(
        String(100),
        nullable=True,
        doc="Código SKU del producto",
    )

    # URL de imagen del producto
    product_image_url: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="URL de imagen del producto mayorista",
    )

    # Precio mayorista unitario en Pesos Mexicanos ($ MXN)
    wholesale_price_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Precio de mayoreo por unidad en $ MXN",
    )

    # Precio regular de venta al público en $ MXN como referencia
    regular_price_mxn: Mapped[Optional[Decimal]] = mapped_column(
        Numeric(12, 2),
        nullable=True,
        doc="Precio regular de venta al público en $ MXN",
    )

    # Cantidad mínima para acceder al precio de mayoreo
    min_wholesale_quantity: Mapped[Decimal] = mapped_column(
        Numeric(10, 2),
        default=Decimal("1.00"),
        nullable=False,
        doc="Cantidad mínima de compra en piezas o kilogramos",
    )

    # Existencias disponibles destinadas a venta B2B
    available_b2b_stock: Mapped[Decimal] = mapped_column(
        Numeric(10, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Existencias físicas apartadas para la red mayorista",
    )

    # Código postal del vendedor
    location_postal_code: Mapped[Optional[str]] = mapped_column(
        String(10),
        nullable=True,
        index=True,
        doc="Código postal de la ubicación física del negocio",
    )

    # Ciudad / Municipio
    location_city: Mapped[Optional[str]] = mapped_column(
        String(100),
        nullable=True,
        index=True,
        doc="Ciudad o delegación donde se ubica el comercio",
    )

    # Estado activo / pausado
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
        doc="Indica si la oferta está activa en el catálogo comunitario",
    )

    # Notas comerciales
    notes: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Condiciones de entrega o notas comerciales del vendedor",
    )

    # Marcas temporales
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # Relaciones de dominio
    tenant = relationship("Tenant", lazy="joined")
