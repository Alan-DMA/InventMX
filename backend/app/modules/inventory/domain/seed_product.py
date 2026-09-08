# Importación del módulo datetime para estampas temporales
from datetime import datetime
# Importación del módulo decimal para precios sugeridos
from decimal import Decimal
# Importación de tipado estático
from typing import Optional
# Importación de UUID para identificación única
import uuid
# Importación de tipos de SQLAlchemy
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Numeric,
    String,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

# Importación de la clase base declarativa
from app.core.database.base import Base


class SeedProduct(Base):
    """
    Modelo de Dominio para el Catálogo Semilla Maestro EAN-13 Oficial de México (Tier 1).
    Permite autocompletado y reconocimiento instantáneo de productos líderes
    (Bimbo, Coca-Cola, Sabritas, Lala, etc.) en < 5ms (RF-29 / Const. Art. 7.5).
    """
    # Nombre de la tabla física en PostgreSQL
    __tablename__ = "seed_products_catalog"
    # Configuración de constraints de esquema y validaciones
    __table_args__ = (
        CheckConstraint("suggested_price_mxn >= 0", name="chk_seed_price_mxn_non_negative"),
        {"schema": "inventmx"},
    )

    # Identificador único UUID del producto semilla
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del registro en catálogo semilla",
    )

    # Código de barras físico oficial EAN-13 / GS1 México
    barcode: Mapped[str] = mapped_column(
        String(50),
        unique=True,
        nullable=False,
        index=True,
        doc="Código de barras oficial indexado para búsqueda en < 5ms",
    )

    # Nombre comercial oficial del producto
    name: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        index=True,
        doc="Nombre comercial del producto en catálogo semilla",
    )

    # Marca o fabricante oficial (ej. Bimbo, Sabritas, Coca-Cola)
    brand: Mapped[Optional[str]] = mapped_column(
        String(100),
        nullable=True,
        doc="Marca comercial del producto",
    )

    # Categoría sugerida por defecto
    category_name: Mapped[str] = mapped_column(
        String(100),
        default="General",
        nullable=False,
        doc="Categoría sugerida para clasificación",
    )

    # Precio de venta sugerido al público en Pesos Mexicanos ($ MXN)
    suggested_price_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Precio sugerido al público en Pesos Mexicanos",
    )

    # URL de imagen o fotografía oficial de referencia
    image_url: Mapped[Optional[str]] = mapped_column(
        String(500),
        nullable=True,
        doc="Enlace a fotografía de referencia del producto",
    )

    # Bandera de verificación oficial de la información
    is_verified: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
        doc="Indica si el producto cuenta con verificación oficial GS1",
    )

    # Estampa de tiempo de registro
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Fecha y hora de registro del producto semilla",
    )
