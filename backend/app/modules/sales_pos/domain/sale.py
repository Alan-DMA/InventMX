# Importación de marcas temporales
from datetime import datetime, timezone
# Importación de precisión decimal
from decimal import Decimal
# Importación de enums estándar
import enum
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import (
    Boolean,
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

# Importación de la clase base declarativa
from app.core.database.base import Base


class SaleStatus(str, enum.Enum):
    """
    Estados del ciclo de vida de una venta (RF-12 / Const. Art. 7.1).
    Transición estricta: DRAFT -> PENDING_PAYMENT -> PAID / COMPLETED o CANCELLED.
    """
    DRAFT = "DRAFT"                        # Venta en borrador o armado de carrito
    PENDING_PAYMENT = "PENDING_PAYMENT"    # Venta con stock apartado pendiente de pago
    PAID = "PAID"                          # Venta cobrada con stock descontado
    COMPLETED = "COMPLETED"                # Venta completada y finalizada en mostrador
    CANCELLED = "CANCELLED"                # Venta anulada con reversión de inventario
    REFUNDED = "REFUNDED"                  # Venta devuelta total o parcialmente


class Sale(Base):
    """
    Modelo de Dominio para la Cabecera de Ventas POS (inventmx.sales).
    Representa el comprobante y transacción de venta en mostrador (RF-08, RF-12).
    """
    # Nombre de la tabla en base de datos
    __tablename__ = "sales"
    # Configuración de constraints y esquema
    __table_args__ = (
        CheckConstraint("total_mxn >= 0", name="chk_sales_total_non_negative"),
        CheckConstraint("subtotal_mxn >= 0", name="chk_sales_subtotal_non_negative"),
        CheckConstraint("discount_mxn >= 0", name="chk_sales_discount_non_negative"),
        CheckConstraint("total_cost_mxn >= 0", name="chk_sales_total_cost_non_negative"),
        {"schema": "inventmx"},
    )

    # Identificador único UUID de la venta
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único de la venta",
    )

    # Identificador del inquilino (Tenant) para aislamiento multi-tenant RLS
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="ID del inquilino propietario de la venta",
    )

    # Identificador del usuario/cajero que procesó la venta
    cashier_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.users.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
        doc="ID del usuario cajero responsable del cobro",
    )

    # Identificador del almacén de donde se descontó la mercancía
    warehouse_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.warehouses.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
        doc="ID del almacén físico de origen del stock",
    )

    # Identificador opcional del cliente en mostrador
    client_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        nullable=True,
        doc="ID opcional del cliente asociado",
    )

    # Folio consecutivo de venta por comercio (ej. VTA-20260908-0001)
    folio: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        index=True,
        doc="Folio consecutivo administrativo de la nota de venta",
    )

    # Estado actual del ciclo de venta
    status: Mapped[SaleStatus] = mapped_column(
        SQLEnum(SaleStatus, name="sale_status_enum", schema="inventmx", native_enum=True),
        default=SaleStatus.COMPLETED,
        nullable=False,
        index=True,
        doc="Estado actual de la venta",
    )

    # Subtotal bruto antes de descuentos e impuestos en Pesos Mexicanos ($ MXN)
    subtotal_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Suma bruta de los productos en Pesos Mexicanos",
    )

    # Descuento general aplicado a la venta en Pesos Mexicanos ($ MXN)
    discount_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Descuento total en Pesos Mexicanos",
    )

    # Impuestos trasladados en Pesos Mexicanos ($ MXN)
    tax_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Impuestos calculados en Pesos Mexicanos",
    )

    # Total neto final a cobrar en Pesos Mexicanos ($ MXN)
    total_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Importe total neto de la venta en Pesos Mexicanos",
    )

    # Costo histórico total congelado al momento de la venta ($ MXN) para rentabilidad
    total_cost_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Costo de mercancía vendida congelado para cálculo de rentabilidad neta (RF-20)",
    )

    # Notas u observaciones del cajero
    notes: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Notas u observaciones de la nota de venta",
    )

    # Estampa de tiempo de creación
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=func.now(),
        nullable=False,
        index=True,
        doc="Fecha y hora de emisión del ticket",
    )

    # Estampa de tiempo de última actualización
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=func.now(),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
        doc="Fecha y hora de última modificación",
    )

    # Relación uno-a-muchos con las partidas de la venta
    items: Mapped[List["SaleItem"]] = relationship(
        "SaleItem",
        back_populates="sale",
        cascade="all, delete-orphan",
        lazy="selectin",
        doc="Lista de partidas o productos incluidos en la venta",
    )

    # Relación con el usuario cajero
    cashier: Mapped["User"] = relationship(
        "User",
        lazy="selectin",
        foreign_keys=[cashier_id],
        doc="Usuario cajero que emitió la venta",
    )

    # Relación con el almacén físico
    warehouse: Mapped["Warehouse"] = relationship(
        "Warehouse",
        lazy="selectin",
        foreign_keys=[warehouse_id],
        doc="Almacén físico donde se descontó el stock",
    )


class SaleItem(Base):
    """
    Modelo de Dominio para las Partidas Individuales de Venta (inventmx.sale_items).
    Almacena el snapshot congelado del producto, su precio y su costo unitario histórico.
    """
    # Nombre de la tabla en base de datos
    __tablename__ = "sale_items"
    # Configuración de constraints y esquema
    __table_args__ = (
        CheckConstraint("quantity > 0", name="chk_sale_items_qty_positive"),
        CheckConstraint("unit_price_mxn >= 0", name="chk_sale_items_price_non_negative"),
        CheckConstraint("unit_cost_mxn >= 0", name="chk_sale_items_cost_non_negative"),
        CheckConstraint("total_mxn >= 0", name="chk_sale_items_total_non_negative"),
        {"schema": "inventmx"},
    )

    # Identificador único de la partida
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único de la partida de venta",
    )

    # Identificador del inquilino (Tenant) para aislamiento multi-tenant RLS
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="ID del inquilino propietario",
    )

    # Identificador de la venta cabecera
    sale_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.sales.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="ID de la venta a la que pertenece la partida",
    )

    # Identificador del producto físico (NULL si es combo o ítem no asociado)
    product_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.products.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        doc="ID del producto físico vendido",
    )

    # Identificador del combo o paquete promocional (NULL si es producto normal)
    combo_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.combos.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        doc="ID del combo vendido",
    )

    # Snapshot inmutable del nombre del producto al momento de cobrar
    product_name: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        doc="Nombre comercial congelado al momento del cobro",
    )

    # Snapshot inmutable del código SKU
    product_sku: Mapped[Optional[str]] = mapped_column(
        String(50),
        nullable=True,
        doc="SKU del producto congelado al momento del cobro",
    )

    # Cantidad vendida (admite fracciones en kg o piezas enteras)
    quantity: Mapped[Decimal] = mapped_column(
        Numeric(12, 3),
        nullable=False,
        doc="Cantidad de unidades o peso vendido",
    )

    # Precio unitario cobrado al cliente en Pesos Mexicanos ($ MXN)
    unit_price_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Precio unitario de venta congelado",
    )

    # Costo unitario promedio histórico congelado ($ MXN) para rentabilidad
    unit_cost_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Costo de adquisición congelado para cálculo de utilidad real",
    )

    # Subtotal de la partida (quantity * unit_price_mxn)
    subtotal_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Subtotal bruto de la partida",
    )

    # Descuento específico de la partida en Pesos Mexicanos ($ MXN)
    discount_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Descuento aplicado a esta partida",
    )

    # Total neto de la partida (subtotal_mxn - discount_mxn)
    total_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Total neto facturado de la partida",
    )

    # Bandera que indica si el producto fue creado sobre la marcha (Lazy Loading RF-09)
    is_on_the_fly: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
        doc="Indica si el producto fue creado al vuelo durante la venta",
    )

    # Estampa de tiempo de registro
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=func.now(),
        nullable=False,
        doc="Estampa de tiempo del ítem",
    )

    # Relación inversa con la venta
    sale: Mapped["Sale"] = relationship("Sale", back_populates="items")

    # Relación con el producto físico
    product: Mapped[Optional["Product"]] = relationship("Product", lazy="selectin")

    # Relación con el combo
    combo: Mapped[Optional["Combo"]] = relationship("Combo", lazy="selectin")
