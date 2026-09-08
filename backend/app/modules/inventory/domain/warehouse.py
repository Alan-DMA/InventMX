# Importación del módulo datetime para marcas de tiempo
from datetime import datetime
# Importación de tipado estático
from typing import List, Optional
# Importación de UUID para claves primarias
import uuid
# Importación de tipos de columnas de SQLAlchemy
from sqlalchemy import Boolean, DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa
from app.core.database.base import Base


class Warehouse(Base):
    """
    Modelo de Dominio para la entidad Almacén / Sucursal en el schema 'inventmx'.
    Representa una ubicación física de resguardo y control de existencias de inventario.
    """
    # Nombre de la tabla física en PostgreSQL
    __tablename__ = "warehouses"
    # Esquema específico de inventario
    __table_args__ = {"schema": "inventmx"}

    # Identificador único UUID del almacén
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del almacén",
    )

    # Identificador del comercio propietario (Aislamiento Multi-tenant RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el inquilino/comercio dueño del almacén",
    )

    # Nombre descriptivo del almacén (ej. 'Almacén Principal', 'Bodega Tienda')
    name: Mapped[str] = mapped_column(
        String(150),
        nullable=False,
        doc="Nombre de la ubicación o almacén físico",
    )

    # Indicador de almacén predeterminado para ventas y entradas rápidas
    is_default: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
        doc="Determina si es el almacén por defecto del comercio",
    )

    # Fecha y hora de creación
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Estampa de tiempo de registro del almacén",
    )

    # Relación bidireccional con las existencias de productos en este almacén
    stocks: Mapped[List["ProductStock"]] = relationship(
        "ProductStock",
        back_populates="warehouse",
        cascade="all, delete-orphan",
        doc="Existencias físicas de productos vinculadas a este almacén",
    )
