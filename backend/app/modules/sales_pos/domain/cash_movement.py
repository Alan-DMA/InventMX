# Importación de marcas temporales
from datetime import datetime, timezone
# Importación de precisión decimal para montos monetarios en MXN
from decimal import Decimal
# Importación de enumeraciones nativas de Python
from enum import Enum
# Importación de tipado estático
from typing import Optional
# Importación de identificadores únicos universales UUID
import uuid
# Importación de componentes de SQLAlchemy
from sqlalchemy import (
    CheckConstraint,
    DateTime,
    Enum as SQLEnum,
    ForeignKey,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa de base de datos
from app.core.database.base import Base


class CashMovementType(str, Enum):
    """
    Tipos de Movimientos Manuales de Efectivo en Caja Chica.
    """
    # Entrada manual de efectivo (depósito de cambio, aportación del dueño)
    CASH_IN = "CASH_IN"
    # Salida manual de efectivo (pago a proveedores menores, retiro de exceso / corte parcial, gasto operativo)
    CASH_OUT = "CASH_OUT"


class CashMovement(Base):
    """
    Modelo de Dominio para Movimientos Manuales de Caja Chica (RF-16 / Const. Art. 3.3).
    Registra entradas y salidas de efectivo dentro de un turno activo con motivo y usuario responsable.
    """
    # Nombre físico de la tabla en PostgreSQL
    __tablename__ = "cash_movements"
    # Constraints de tabla y esquema
    __table_args__ = (
        CheckConstraint("amount_mxn > 0", name="chk_cash_movements_amount_positive"),
        {"schema": "inventmx"},
    )

    # Identificador único universal del movimiento de caja
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del movimiento manual de efectivo",
    )

    # Identificador del inquilino / comercio para aislamiento multi-inquilino (RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        doc="Identificador del inquilino propietario",
    )

    # Identificador del turno de caja al que pertenece el movimiento
    shift_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.cash_shifts.id", ondelete="CASCADE"),
        nullable=False,
        doc="Identificador del turno de caja activo",
    )

    # Tipo de movimiento manual (CASH_IN o CASH_OUT)
    movement_type: Mapped[CashMovementType] = mapped_column(
        SQLEnum(
            CashMovementType,
            name="cash_movement_type_enum",
            schema="inventmx",
            native_enum=True,
            values_callable=lambda obj: [e.value for e in obj],
        ),
        nullable=False,
        doc="Tipo de movimiento de efectivo (Entrada o Salida)",
    )

    # Monto del movimiento en Pesos Mexicanos (siempre estrictamente positivo)
    amount_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Monto monetario en Pesos Mexicanos del movimiento",
    )

    # Motivo, concepto o razón del movimiento
    reason: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        doc="Razón descriptiva del movimiento (ej: Pago de garrafón de agua, Aporte de cambio)",
    )

    # Observaciones o detalles adicionales
    notes: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Detalles adicionales o notas de justificación",
    )

    # Identificador del supervisor que autorizó el movimiento (opcional)
    authorized_by_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.users.id", ondelete="SET NULL"),
        nullable=True,
        doc="Supervisor o encargado que autorizó el retiro o entrada",
    )

    # Identificador del usuario cajero que registró el movimiento
    created_by_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.users.id", ondelete="RESTRICT"),
        nullable=False,
        doc="Usuario cajero que efectuó el registro del movimiento",
    )

    # Marca de tiempo de registro del movimiento
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Fecha y hora de registro del movimiento",
    )

    # Relación inversa con el Turno de Caja
    shift: Mapped["CashShift"] = relationship(
        "CashShift",
        back_populates="movements",
        doc="Turno de caja al que pertenece el movimiento",
    )
