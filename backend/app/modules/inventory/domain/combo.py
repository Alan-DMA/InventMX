# Importación del módulo datetime para marcas de tiempo
from datetime import datetime
# Importación del módulo decimal para precisión en precios y cantidades
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de UUID para claves primarias y foráneas
import uuid
# Importación de tipos de columnas y constructores de SQLAlchemy
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa
from app.core.database.base import Base


class Combo(Base):
    """
    Modelo de Dominio para la entidad Combo / Promoción en el schema 'inventmx' (RF-03).
    Permite agrupar múltiples productos individuales bajo un precio único en MXN.
    Al venderse en POS, descuenta atómicamente el stock de cada artículo componente.
    """
    # Nombre de la tabla física en PostgreSQL
    __tablename__ = "combos"
    # Constraints de esquema y unicidad
    __table_args__ = (
        UniqueConstraint("tenant_id", "sku", name="uq_combos_tenant_sku"),
        CheckConstraint("price_mxn >= 0", name="chk_combos_price_mxn_non_negative"),
        {"schema": "inventmx"},
    )

    # Identificador único UUID del combo
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del combo",
    )

    # Identificador del comercio propietario (Aislamiento Multi-tenant RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el inquilino/comercio dueño del combo",
    )

    # Nombre comercial del combo (ej. 'Combo Paquete Fiesta: 2 Refrescos + 1 Botana')
    name: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        doc="Nombre de la promoción o paquete",
    )

    # Descripción opcional del contenido del combo
    description: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Descripción detallada de la oferta o promoción",
    )

    # Precio único de venta en Pesos Mexicanos (Moneda Base MXN)
    price_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Precio de venta consolidado en Pesos Mexicanos ($ MXN)",
    )

    # Código interno SKU del combo (formato 'NEX-XXXXX')
    sku: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        doc="Código SKU del combo",
    )

    # Código de barras opcional para escaneo en caja
    barcode: Mapped[Optional[str]] = mapped_column(
        String(50),
        nullable=True,
        index=True,
        doc="Código de barras EAN/UPC asignado a la promoción",
    )

    # Fotografía o banner de la promoción
    image_url: Mapped[Optional[str]] = mapped_column(
        String(500),
        nullable=True,
        doc="Enlace a la imagen del combo",
    )

    # Estado activo/inactivo para ventas
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
        doc="Indica si la promoción está vigente",
    )

    # Fecha y hora de creación
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Estampa de tiempo de alta del combo",
    )

    # Fecha y hora de última modificación
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
        doc="Estampa de tiempo de última actualización",
    )

    # Relación bidireccional con los ítems que componen el combo
    items: Mapped[List["ComboItem"]] = relationship(
        "ComboItem",
        back_populates="combo",
        cascade="all, delete-orphan",
        doc="Lista de productos y cantidades que componen este paquete",
    )


class ComboItem(Base):
    """
    Modelo de Dominio para la entidad ComboItem.
    Representa un producto individual y la cantidad requerida dentro de un Combo.
    """
    __tablename__ = "combo_items"
    __table_args__ = (
        UniqueConstraint("combo_id", "product_id", name="uq_combo_items_combo_product"),
        CheckConstraint("quantity > 0", name="chk_combo_items_quantity_positive"),
        {"schema": "inventmx"},
    )

    # Identificador único UUID del ítem de combo
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del ítem",
    )

    # Identificador del comercio propietario (RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        doc="Clave foránea hacia el comercio dueño",
    )

    # Identificador del combo padre
    combo_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.combos.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el combo contenedor",
    )

    # Identificador del producto individual
    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.products.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el producto componente",
    )

    # Cantidad de este producto que incluye el paquete (ej. 2.0 piezas)
    quantity: Mapped[Decimal] = mapped_column(
        Numeric(10, 2),
        nullable=False,
        doc="Cantidad de unidades requeridas de este producto para armar 1 combo",
    )

    # Relación inversa con el combo padre
    combo: Mapped["Combo"] = relationship(
        "Combo",
        back_populates="items",
        doc="Combo padre al que pertenece este ítem",
    )

    # Relación directa con el producto componente
    product: Mapped["Product"] = relationship(
        "Product",
        doc="Entidad del producto individual que forma parte del combo",
    )
