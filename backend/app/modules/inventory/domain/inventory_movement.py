# Importación del módulo datetime para marcas de tiempo inmutables
from datetime import datetime
# Importación del módulo decimal para precisión en existencias y costos
from decimal import Decimal
# Importación del módulo enum estándar de Python
import enum
# Importación de tipado estático
from typing import Optional
# Importación de UUID para identificadores
import uuid
# Importación de tipos de columnas y constructores de SQLAlchemy
from sqlalchemy import (
    DateTime,
    Enum as SQLEnum,
    ForeignKey,
    Numeric,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa
from app.core.database.base import Base


class MovementType(str, enum.Enum):
    """
    Tipos oficiales de movimientos de inventario registrados en el Kardex (Const. Art. 7.1).
    """
    PURCHASE_ENTRY = "PURCHASE_ENTRY"        # Entrada por recepción de orden de compra a proveedor
    SALE_EXIT = "SALE_EXIT"                  # Salida por venta cobrada en punto de venta (POS)
    SALE_CANCEL = "SALE_CANCEL"              # Reincorporación de stock por anulación/cancelación de venta
    SALE_RETURN = "SALE_RETURN"              # Devolución física de mercancía por el cliente
    ADJUSTMENT_IN = "ADJUSTMENT_IN"          # Ajuste manual positivo por conteo físico o sobrante
    ADJUSTMENT_OUT = "ADJUSTMENT_OUT"        # Ajuste manual negativo por corrección o faltante
    TRANSFER_IN = "TRANSFER_IN"              # Entrada a almacén destino por traslado interno
    TRANSFER_OUT = "TRANSFER_OUT"            # Salida de almacén origen por traslado interno
    WASTE_MERMA = "WASTE_MERMA"              # Salida por producto dañado, caducado o merma
    RESERVATION_HOLD = "RESERVATION_HOLD"    # Bloqueo temporal por venta en proceso (TTL 15 min)
    RESERVATION_RELEASE = "RESERVATION_RELEASE" # Liberación de reserva por expiración o cancelación


class InventoryMovement(Base):
    """
    Modelo de Dominio para el Libro Mayor de Kardex (inventory_movements).
    Es una tabla de auditoría inmutable append-only que registra cada cambio físico
    en las existencias de un producto en un almacén determinado (RF-05 / Const. Art. 7.1).
    """
    # Nombre de la tabla en base de datos
    __tablename__ = "inventory_movements"
    # Argumentos de tabla y esquema
    __table_args__ = (
        {"schema": "inventmx"},
    )

    # Identificador único UUID del asiento en el Kardex
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único inmutable del asiento en Kardex",
    )

    # Identificador del inquilino (Tenant) para aislamiento multi-tenant RLS
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="ID del inquilino propietario del movimiento",
    )

    # Identificador del producto afectado
    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.products.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="ID del producto físico afectado",
    )

    # Identificador del almacén o sucursal donde ocurrió la alteración
    warehouse_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.warehouses.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
        doc="ID del almacén físico donde se registró la alteración",
    )

    # Identificador opcional del almacén de origen en caso de traslados
    from_warehouse_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.warehouses.id", ondelete="SET NULL"),
        nullable=True,
        doc="ID del almacén origen en traslados internos",
    )

    # Identificador opcional del almacén de destino en caso de traslados
    to_warehouse_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.warehouses.id", ondelete="SET NULL"),
        nullable=True,
        doc="ID del almacén destino en traslados internos",
    )

    # Identificador del usuario que ejecutó o autorizó el movimiento
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        doc="ID del usuario responsable de la transacción",
    )

    # Tipo de movimiento catalogado
    movement_type: Mapped[MovementType] = mapped_column(
        SQLEnum(MovementType, name="movement_type_enum", schema="inventmx", native_enum=True),
        nullable=False,
        index=True,
        doc="Naturaleza contable del movimiento físico",
    )

    # Cantidad alterada (Positiva para entradas, Negativa para salidas)
    quantity: Mapped[Decimal] = mapped_column(
        Numeric(12, 3),
        nullable=False,
        doc="Magnitud del movimiento (con signo algebraico)",
    )

    # Existencia física previa al movimiento
    previous_stock: Mapped[Decimal] = mapped_column(
        Numeric(12, 3),
        nullable=False,
        doc="Saldo de existencias antes de aplicar el movimiento",
    )

    # Nueva existencia física resultante tras el movimiento
    new_stock: Mapped[Decimal] = mapped_column(
        Numeric(12, 3),
        nullable=False,
        doc="Saldo de existencias después de aplicar el movimiento",
    )

    # Costo unitario promedio histórico en Pesos Mexicanos ($ MXN)
    unit_cost_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Costo unitario promedio valuado en Pesos Mexicanos al momento del asiento",
    )

    # Identificador del documento o entidad origen (Venta ID, Compra ID, Traslado ID)
    reference_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        nullable=True,
        index=True,
        doc="UUID de referencia al documento de origen",
    )

    # Motivo, nota u observación explicativa
    notes: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Motivo detallado o justificación del movimiento",
    )

    # Estampa de tiempo inmutable del registro
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        index=True,
        doc="Estampa de tiempo del asiento contable",
    )

    # Relaciones ORM
    product: Mapped["Product"] = relationship("Product", foreign_keys=[product_id], lazy="selectin")
    warehouse: Mapped["Warehouse"] = relationship("Warehouse", foreign_keys=[warehouse_id], lazy="selectin")
    from_warehouse: Mapped[Optional["Warehouse"]] = relationship("Warehouse", foreign_keys=[from_warehouse_id], lazy="selectin")
    to_warehouse: Mapped[Optional["Warehouse"]] = relationship("Warehouse", foreign_keys=[to_warehouse_id], lazy="selectin")
    user: Mapped[Optional["User"]] = relationship("User", foreign_keys=[user_id], lazy="selectin")
