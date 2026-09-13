# Importación de enumeraciones
import enum
# Importación del módulo datetime para marcas temporales
from datetime import datetime
# Importación del módulo decimal para importes monetarios en MXN
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de constructs de SQLAlchemy
from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import ENUM as PG_ENUM, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa y esquema del sistema
from app.core.database.base import Base, SCHEMA


class B2BOrderStatus(str, enum.Enum):
    """Estados del ciclo de vida de un pedido B2B entre comercios."""
    PENDING = "PENDING"       # Solicitud enviada por el comprador
    ACCEPTED = "ACCEPTED"     # Aceptada por el vendedor (convierte a Orden de Compra)
    REJECTED = "REJECTED"     # Rechazada por el vendedor
    COMPLETED = "COMPLETED"   # Mercancía entregada y liquidada
    CANCELLED = "CANCELLED"   # Cancelada antes de entrega


class B2BDeliveryType(str, enum.Enum):
    """Modalidad de entrega para el pedido mayorista."""
    PICKUP = "PICKUP"         # El comprador recoge en la tienda del vendedor
    DELIVERY = "DELIVERY"     # El vendedor entrega a domicilio


class B2BOrder(Base):
    """
    Modelo de Dominio para pedidos mayoristas B2B entre dos comercios independientes (RF-27).
    Garantiza consistencia transaccional y sincronización multi-tenant (Const. Art. 7.5).
    """
    __tablename__ = "b2b_orders"
    __table_args__ = (
        CheckConstraint("total_mxn >= 0", name="chk_b2b_order_total_non_negative"),
        {"schema": SCHEMA},
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del pedido B2B",
    )

    order_number: Mapped[str] = mapped_column(
        String(50),
        unique=True,
        nullable=False,
        index=True,
        doc="Folio único del pedido B2B (ej: B2B-2026-0001)",
    )

    buyer_tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Comercio que realiza la compra mayorista",
    )

    seller_tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Comercio vendedor que abastece el pedido",
    )

    status: Mapped[B2BOrderStatus] = mapped_column(
        PG_ENUM(B2BOrderStatus, name="b2b_order_status_enum", schema=SCHEMA, create_type=False),
        default=B2BOrderStatus.PENDING,
        nullable=False,
        index=True,
        doc="Estado operativo del pedido",
    )

    total_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Total del pedido en Pesos Mexicanos ($ MXN)",
    )

    delivery_type: Mapped[B2BDeliveryType] = mapped_column(
        PG_ENUM(B2BDeliveryType, name="b2b_delivery_type_enum", schema=SCHEMA, create_type=False),
        default=B2BDeliveryType.PICKUP,
        nullable=False,
        doc="Tipo de entrega",
    )

    delivery_address: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Dirección acordada si es entrega a domicilio",
    )

    notes: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Instrucciones o acuerdos comerciales",
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # Relaciones de dominio
    items: Mapped[List["B2BOrderItem"]] = relationship(
        "B2BOrderItem",
        back_populates="order",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    buyer_tenant = relationship("Tenant", foreign_keys=[buyer_tenant_id], lazy="joined")
    seller_tenant = relationship("Tenant", foreign_keys=[seller_tenant_id], lazy="joined")


class B2BOrderItem(Base):
    """
    Renglón de partida individual dentro de un pedido mayorista B2B.
    """
    __tablename__ = "b2b_order_items"
    __table_args__ = (
        CheckConstraint("quantity > 0", name="chk_b2b_order_item_qty_positive"),
        CheckConstraint("unit_price_mxn >= 0", name="chk_b2b_order_item_price_non_negative"),
        CheckConstraint("subtotal_mxn >= 0", name="chk_b2b_order_item_subtotal_non_negative"),
        {"schema": SCHEMA},
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del renglón de pedido",
    )

    b2b_order_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.b2b_orders.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Pedido B2B asociado",
    )

    b2b_listing_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.b2b_listings.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
        doc="Oferta mayorista B2B origen",
    )

    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.products.id", ondelete="RESTRICT"),
        nullable=False,
        doc="Producto del vendedor",
    )

    product_name: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        doc="Nombre congelado del producto al momento de pedir",
    )

    quantity: Mapped[Decimal] = mapped_column(
        Numeric(10, 2),
        nullable=False,
        doc="Cantidad de unidades mayoristas",
    )

    unit_price_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Precio pactado en $ MXN",
    )

    subtotal_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Subtotal del renglón en $ MXN",
    )

    # Relación inversa
    order: Mapped["B2BOrder"] = relationship("B2BOrder", back_populates="items")
