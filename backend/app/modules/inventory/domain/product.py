# Importación del módulo datetime para marcas temporales
from datetime import datetime
# Importación del módulo decimal para manejo monetario de alta precisión
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de UUID para claves primarias
import uuid
# Importación de tipos y constructores de SQLAlchemy
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Numeric,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa
from app.core.database.base import Base


class Product(Base):
    """
    Modelo de Dominio para la entidad Producto en el schema 'inventmx'.
    Implementa la regla sagrada de los 3 Campos Vitales:
    1. name: Nombre comercial del artículo
    2. price_mxn: Precio de venta en Pesos Mexicanos (Moneda Base)
    3. current_stock: Existencias físicas (a través de la relación 'stocks')
    """
    # Nombre de la tabla física en PostgreSQL
    __tablename__ = "products"
    # Configuración de constraints de esquema y unicidad
    __table_args__ = (
        # Unicidad de SKU por comercio
        UniqueConstraint("tenant_id", "sku", name="uq_products_tenant_sku"),
        # Validación de no negatividad en precio de venta en MXN
        CheckConstraint("price_mxn >= 0", name="chk_products_price_mxn_non_negative"),
        # Validación de no negatividad en costo de compra en MXN
        CheckConstraint("cost_mxn >= 0", name="chk_products_cost_mxn_non_negative"),
        # Validación de umbral de stock mínimo no negativo
        CheckConstraint("min_stock_alert >= 0", name="chk_products_min_stock_non_negative"),
        # Esquema específico de inventario
        {"schema": "inventmx"},
    )

    # Identificador único UUID del producto
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único universal del producto",
    )

    # Identificador del comercio propietario (Aislamiento Multi-tenant RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el comercio dueño del producto",
    )

    # Identificador opcional de categoría
    category_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.categories.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        doc="Clave foránea hacia la categoría de clasificación",
    )

    # Campo Vital 1: Nombre comercial del artículo
    name: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        doc="Nombre comercial o descripción corta del producto",
    )

    # Campo Vital 2: Precio de venta en Pesos Mexicanos (MXN)
    price_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Precio de venta final al público en Pesos Mexicanos ($ MXN)",
    )

    # Costo de adquisición o compra en Pesos Mexicanos (MXN)
    cost_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Costo de compra en Pesos Mexicanos ($ MXN)",
    )

    # Costo opcional en Dólares para artículos importados (RF-02)
    cost_usd_import: Mapped[Optional[Decimal]] = mapped_column(
        Numeric(12, 4),
        nullable=True,
        doc="Costo de importación opcional en USD para referencia cambiaria",
    )

    # Código interno de identificación SKU (autogenerado con formato 'NEX-XXXXX')
    sku: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        doc="Código único SKU de identificación interna",
    )

    # Código de barras físico EAN-13 / UPC escaneable
    barcode: Mapped[Optional[str]] = mapped_column(
        String(50),
        nullable=True,
        index=True,
        doc="Código de barras EAN/UPC para escaneo en punto de venta",
    )

    # Umbral de advertencia para stock bajo
    min_stock_alert: Mapped[Decimal] = mapped_column(
        Numeric(10, 2),
        default=Decimal("5.00"),
        nullable=False,
        doc="Cantidad mínima para disparar alertas de reabastecimiento",
    )

    # URL o ruta a la imagen del producto
    image_url: Mapped[Optional[str]] = mapped_column(
        String(500),
        nullable=True,
        doc="Enlace a la fotografía o miniatura del producto",
    )

    # Estado activo/inactivo en el catálogo de ventas
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
        doc="Indica si el producto está disponible para venta",
    )

    # Fecha y hora de creación
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Estampa de tiempo de registro del producto",
    )

    # Fecha y hora de última actualización
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
        doc="Estampa de tiempo de última modificación",
    )

    # Relación con la Categoría
    category: Mapped[Optional["Category"]] = relationship(
        "Category",
        back_populates="products",
        doc="Categoría asignada al producto",
    )

    # Relación con las existencias en cada almacén
    stocks: Mapped[List["ProductStock"]] = relationship(
        "ProductStock",
        back_populates="product",
        cascade="all, delete-orphan",
        doc="Listado de existencias del producto en cada almacén del comercio",
    )
