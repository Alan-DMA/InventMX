# Importación del módulo datetime para marcas temporales
from datetime import datetime
# Importación del módulo decimal para precisión en cantidades
from decimal import Decimal
# Importación de UUID para claves primarias
import uuid
# Importación de tipos de columnas de SQLAlchemy
from sqlalchemy import (
    DateTime,
    ForeignKey,
    Numeric,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa
from app.core.database.base import Base


class ProductStock(Base):
    """
    Modelo de Dominio para la entidad ProductStock en el schema 'inventmx'.
    Controla las existencias físicas y el stock reservado por producto y almacén (Campo Vital 3).
    """
    # Nombre de la tabla física en PostgreSQL
    __tablename__ = "product_stocks"
    # Constraints de unicidad por comercio, producto y almacén
    __table_args__ = (
        UniqueConstraint(
            "tenant_id",
            "product_id",
            "warehouse_id",
            name="uq_product_stocks_tenant_prod_wh",
        ),
        {"schema": "inventmx"},
    )

    # Identificador único UUID del registro de stock
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del registro de existencias",
    )

    # Identificador del comercio propietario (Aislamiento Multi-tenant RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el inquilino/comercio dueño del stock",
    )

    # Identificador del producto
    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.products.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el producto",
    )

    # Identificador del almacén o sucursal donde reside la mercancía
    warehouse_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.warehouses.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el almacén correspondiente",
    )

    # Campo Vital 3: Existencias físicas actuales disponibles
    current_stock: Mapped[Decimal] = mapped_column(
        Numeric(10, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Cantidad física disponible en este almacén",
    )

    # Cantidad apartada en carritos o ventas en proceso (expira en 15 min - RF-06)
    reserved_stock: Mapped[Decimal] = mapped_column(
        Numeric(10, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Cantidad temporalmente reservada para ventas en checkout",
    )

    # Estampa de tiempo de última actualización de existencias
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
        doc="Estampa de tiempo de última mutación del stock",
    )

    # Relación inversa con el Producto
    product: Mapped["Product"] = relationship(
        "Product",
        back_populates="stocks",
        doc="Producto al que corresponden estas existencias",
    )

    # Relación inversa con el Almacén
    warehouse: Mapped["Warehouse"] = relationship(
        "Warehouse",
        back_populates="stocks",
        doc="Almacén donde se encuentra resguardado el stock",
    )
