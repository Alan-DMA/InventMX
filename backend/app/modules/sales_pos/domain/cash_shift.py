# Importación de marcas temporales y zonas horarias
from datetime import datetime, timezone
# Importación de precisión decimal para montos monetarios en MXN
from decimal import Decimal
# Importación de enumeraciones nativas de Python
from enum import Enum
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores únicos universales UUID
import uuid
# Importación de componentes de SQLAlchemy
from sqlalchemy import (
    CheckConstraint,
    DateTime,
    Enum as SQLEnum,
    ForeignKey,
    Numeric,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa de base de datos
from app.core.database.base import Base


class ShiftStatus(str, Enum):
    """
    Estados posibles de un Turno de Caja (Sesión de Caja en POS).
    """
    # Turno actualmente abierto y operativo en caja
    OPEN = "OPEN"
    # Turno cerrado con arqueo físico concluido
    CLOSED = "CLOSED"


class DifferenceStatus(str, Enum):
    """
    Clasificación del resultado del arqueo de caja (conteo físico vs esperado).
    """
    # Conteo físico coincide exactamente con el saldo teórico del sistema ($0.00 de diferencia)
    EXACT = "EXACT"
    # El dinero físico en caja supera al saldo esperado por el sistema (Sobrante)
    SURPLUS = "SURPLUS"
    # El dinero físico en caja es inferior al saldo esperado por el sistema (Faltante)
    SHORTAGE = "SHORTAGE"


class CashShift(Base):
    """
    Modelo de Dominio para Turnos de Caja y Blindaje de Arqueo (RF-16, RF-17 / Const. Art. 3.3, 7.2).
    Representa una jornada o sesión de trabajo de un cajero con fondo inicial, movimientos y arqueo a ciegas.
    """
    # Nombre físico de la tabla en PostgreSQL
    __tablename__ = "cash_shifts"
    # Constraints de tabla y esquema
    __table_args__ = (
        CheckConstraint("opening_balance_mxn >= 0", name="chk_cash_shifts_opening_balance_positive"),
        {"schema": "inventmx"},
    )

    # Identificador único universal del turno de caja
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del turno de caja",
    )

    # Identificador del inquilino / comercio para aislamiento multi-inquilino (RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        doc="Identificador del inquilino propietario",
    )

    # Identificador del cajero o usuario responsable de la sesión de caja
    cashier_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.users.id", ondelete="RESTRICT"),
        nullable=False,
        doc="Identificador del usuario cajero responsable del turno",
    )

    # Identificador de la sucursal o almacén asignado a la caja
    warehouse_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.warehouses.id", ondelete="SET NULL"),
        nullable=True,
        doc="Sucursal o almacén donde opera la caja",
    )

    # Estado actual del turno de caja (OPEN o CLOSED)
    status: Mapped[ShiftStatus] = mapped_column(
        SQLEnum(
            ShiftStatus,
            name="shift_status_enum",
            schema="inventmx",
            native_enum=True,
            values_callable=lambda obj: [e.value for e in obj],
        ),
        nullable=False,
        default=ShiftStatus.OPEN,
        doc="Estado operativo del turno de caja",
    )

    # Fondo de caja inicial recibido para cambio en Pesos Mexicanos
    opening_balance_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        default=Decimal("0.00"),
        doc="Monto inicial de efectivo asignado a la caja para cambio en MXN",
    )

    # Conteo físico de dinero en efectivo ingresado por el cajero en el arqueo de cierre
    counted_cash_mxn: Mapped[Optional[Decimal]] = mapped_column(
        Numeric(12, 2),
        nullable=True,
        doc="Efectivo físico real contado al momento del cierre de turno",
    )

    # Saldo teórico de efectivo calculado por el sistema en base a ventas y movimientos
    expected_cash_mxn: Mapped[Optional[Decimal]] = mapped_column(
        Numeric(12, 2),
        nullable=True,
        doc="Monto esperado de efectivo según registros del sistema en MXN",
    )

    # Diferencia resultante del arqueo de caja (counted_cash_mxn - expected_cash_mxn)
    difference_mxn: Mapped[Optional[Decimal]] = mapped_column(
        Numeric(12, 2),
        nullable=True,
        doc="Diferencia monetaria resultante del arqueo en MXN",
    )

    # Marca de tiempo de apertura del turno
    opened_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Fecha y hora de apertura del turno",
    )

    # Marca de tiempo de cierre del turno
    closed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        doc="Fecha y hora de finalización y cierre formal del turno",
    )

    # Identificador del usuario que autorizó o ejecutó el cierre del turno
    closed_by_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.users.id", ondelete="SET NULL"),
        nullable=True,
        doc="Usuario que cerró el turno (cajero o supervisor)",
    )

    # Notas, observaciones o justificación de diferencias en el arqueo
    notes: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Observaciones generales o justificación del arqueo de cierre",
    )

    # Marca de tiempo de creación del registro
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Estampa de tiempo de creación",
    )

    # Marca de tiempo de última actualización
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
        doc="Estampa de tiempo de última modificación",
    )

    # Relación uno-a-muchos con los movimientos manuales de caja chica
    movements: Mapped[List["CashMovement"]] = relationship(
        "CashMovement",
        back_populates="shift",
        cascade="all, delete-orphan",
        lazy="selectin",
        doc="Movimientos de entrada y salida manual de efectivo vinculados al turno",
    )
