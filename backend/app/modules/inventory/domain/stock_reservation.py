# Importación del módulo datetime para marcas y expiración temporal
from datetime import datetime
# Importación del módulo decimal para cantidades de reserva
from decimal import Decimal
# Importación del módulo enum estándar de Python
import enum
# Importación de tipado estático
from typing import Optional
# Importación de UUID para claves primarias
import uuid
# Importación de tipos de columnas de SQLAlchemy
from sqlalchemy import (
    CheckConstraint,
    DateTime,
    Enum as SQLEnum,
    ForeignKey,
    Numeric,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa
from app.core.database.base import Base


class ReservationStatus(str, enum.Enum):
    """
    Estados del ciclo de vida de un apartado de existencias con TTL (RF-06).
    """
    PENDING = "PENDING"        # Apartado activo en espera de pago (vigencia 15 min)
    COMMITTED = "COMMITTED"    # Venta concretada exitosamente (descuenta stock físico)
    RELEASED = "RELEASED"      # Apartado cancelado explícitamente por el usuario
    EXPIRED = "EXPIRED"        # Apartado expirado automáticamente por el TTL de 15 minutos


class StockReservation(Base):
    """
    Modelo de Dominio para la entidad StockReservation (Apartados TTL 15 min).
    Garantiza la consistencia ACID en mostrador evitando la sobreventa de productos (RF-06).
    """
    # Nombre de la tabla física en PostgreSQL
    __tablename__ = "stock_reservations"
    # Constraints de esquema y cantidad positiva
    __table_args__ = (
        CheckConstraint("quantity > 0", name="chk_stock_reservations_quantity_positive"),
        {"schema": "inventmx"},
    )

    # Identificador único UUID de la reserva
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del apartado",
    )

    # Identificador del comercio propietario (Aislamiento Multi-tenant RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el inquilino/comercio dueño del registro",
    )

    # Identificador del producto apartado
    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.products.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el producto",
    )

    # Identificador del almacén donde se apartan las existencias
    warehouse_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.warehouses.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el almacén de resguardo",
    )

    # Cantidad de unidades apartadas
    quantity: Mapped[Decimal] = mapped_column(
        Numeric(10, 2),
        nullable=False,
        doc="Cantidad de existencias apartadas",
    )

    # Estado actual del ciclo de vida del apartado
    status: Mapped[ReservationStatus] = mapped_column(
        SQLEnum(ReservationStatus, name="reservation_status_enum", schema="inventmx"),
        default=ReservationStatus.PENDING,
        nullable=False,
        index=True,
        doc="Estado de vigencia del apartado",
    )

    # Identificador de la venta o sesión en proceso (opcional)
    reference_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        nullable=True,
        doc="UUID de la venta o carrito que originó el apartado",
    )

    # Fecha y hora exacta de expiración (por defecto creación + 15 minutos)
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        index=True,
        doc="Estampa de tiempo límite para concretar la venta antes de liberar stock",
    )

    # Fecha de creación del apartado
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Estampa de tiempo de emisión del apartado",
    )

    # Relación con el Producto
    product: Mapped["Product"] = relationship(
        "Product",
        doc="Producto asociado a la reserva",
    )

    # Relación con el Almacén
    warehouse: Mapped["Warehouse"] = relationship(
        "Warehouse",
        doc="Almacén donde se encuentra la reserva",
    )
