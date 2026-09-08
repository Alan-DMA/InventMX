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
    de existencias con fecha, usuario responsable, almacén y costo unitario en MXN.
    """
    # Nombre de la tabla física en PostgreSQL
    __tablename__ = "inventory_movements"
    # Configuración del esquema específico
    __table_args__ = {"schema": "inventmx"}

    # Identificador único UUID del movimiento
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del movimiento de Kardex",
    )

    # Identificador del comercio propietario (Aislamiento Multi-tenant RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el comercio dueño del registro",
    )

    # Identificador del producto afectado
    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.products.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el producto",
    )

    # Identificador del almacén donde ocurre la mutación
    warehouse_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.warehouses.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el almacén afectado",
    )

    # Almacén de origen (opcional, aplicable en traslados)
    from_warehouse_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.warehouses.id", ondelete="SET NULL"),
        nullable=True,
        doc="Almacén de origen en traslados internos",
    )

    # Almacén de destino (opcional, aplicable en traslados)
    to_warehouse_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.warehouses.id", ondelete="SET NULL"),
        nullable=True,
        doc="Almacén de destino en traslados internos",
    )

    # Usuario o empleado que autorizó o ejecutó la operación
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.users.id", ondelete="SET NULL"),
        nullable=True,
        doc="Identificador del usuario responsable",
    )

    # Clasificación estandarizada del movimiento de inventario
    movement_type: Mapped[MovementType] = mapped_column(
        SQLEnum(MovementType, name="movement_type_enum", schema="inventmx"),
        nullable=False,
        doc="Tipo de operación en Kardex",
    )

    # Cantidad movida (positiva o negativa según el flujo)
    quantity: Mapped[Decimal] = mapped_column(
        Numeric(10, 2),
        nullable=False,
        doc="Cantidad física ingresada o retirada del almacén",
    )

    # Saldo anterior de existencias en el almacén antes de la operación
    previous_stock: Mapped[Decimal] = mapped_column(
        Numeric(10, 2),
        nullable=False,
        doc="Saldo previo de existencias antes del movimiento",
    )

    # Saldo resultante de existencias tras aplicar la operación
    new_stock: Mapped[Decimal] = mapped_column(
        Numeric(10, 2),
        nullable=False,
        doc="Saldo resultante de existencias después del movimiento",
    )

    # Costo unitario histórico en Pesos Mexicanos al momento del movimiento
    unit_cost_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Costo de adquisición unitario congelado en MXN",
    )

    # Identificador de referencia externa (ID de venta, ID de compra o ID de reserva)
    reference_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        nullable=True,
        doc="UUID de la transacción externa asociada",
    )

    # Notas, justificación o motivo del ajuste
    notes: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Observaciones o justificación operativa",
    )

    # Estampa de tiempo inmutable del movimiento
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        index=True,
        doc="Estampa de tiempo del asiento contable en Kardex",
    )

    # Relación directa con el Producto
    product: Mapped["Product"] = relationship(
        "Product",
        doc="Producto vinculado a este asiento de Kardex",
    )

    # Relación directa con el Almacén
    warehouse: Mapped["Warehouse"] = relationship(
        "Warehouse",
        foreign_keys=[warehouse_id],
        doc="Almacén principal de este movimiento",
    )
