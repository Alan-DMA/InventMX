# Importación del módulo datetime para marcas temporales
from datetime import datetime
# Importación del tipo Optional y List para tipado estático
from typing import List, Optional
# Importación de UUID para identificadores universales
import uuid
# Importación de tipos de columnas y constructores de SQLAlchemy
from sqlalchemy import DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa del ORM
from app.core.database.base import Base


class Category(Base):
    """
    Modelo de Dominio para la entidad Categoría en el schema 'inventmx'.
    Permite clasificar y organizar productos dentro del comercio multi-tenant.
    """
    # Nombre de la tabla física en PostgreSQL
    __tablename__ = "categories"
    # Esquema específico de inventario y aislamiento
    __table_args__ = {"schema": "inventmx"}

    # Identificador único UUID de la categoría
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único universal de la categoría",
    )

    # Identificador del comercio propietario (Aislamiento Multi-tenant RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el inquilino/comercio dueño del registro",
    )

    # Nombre comercial de la categoría (ej. 'Abarrotes', 'Bebidas', 'Lácteos')
    name: Mapped[str] = mapped_column(
        String(100),
        nullable=False,
        doc="Nombre descriptivo de la categoría de productos",
    )

    # Descripción opcional o notas adicionales
    description: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Descripción detallada de la clasificación de artículos",
    )

    # Fecha y hora de creación del registro
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Estampa de tiempo de alta de la categoría",
    )

    # Relación bidireccional con los productos clasificados bajo esta categoría
    products: Mapped[List["Product"]] = relationship(
        "Product",
        back_populates="category",
        cascade="all, delete-orphan",
        doc="Listado de productos asociados a esta categoría",
    )
