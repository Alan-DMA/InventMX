# Importación de enumeraciones
import enum
# Importación de precisión decimal
from decimal import Decimal
# Importación de fechas y marcas de tiempo
from datetime import date, datetime, timezone
# Importación de identificadores UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import (
    CheckConstraint,
    Column,
    Date,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

# Importación de la base declarativa
from app.core.database.base import Base


class PurchaseOrderStatus(str, enum.Enum):
    """
    Ciclo de vida de una orden de compra / abastecimiento.
    """
    DRAFT = "DRAFT"
    SENT = "SENT"
    CONFIRMED = "CONFIRMED"
    PARTIALLY_RECEIVED = "PARTIALLY_RECEIVED"
    RECEIVED = "RECEIVED"
    CANCELLED = "CANCELLED"


class PurchaseOrder(Base):
    """
    Cabecera de Orden de Compra a Proveedor en Pesos Mexicanos ($ MXN) (RF-15, RF-17).
    """
    __tablename__ = "purchase_orders"
    __table_args__ = (
        CheckConstraint("subtotal_mxn >= 0", name="chk_purchase_orders_subtotal_mxn"),
        CheckConstraint("tax_mxn >= 0", name="chk_purchase_orders_tax_mxn"),
        CheckConstraint("total_mxn >= 0", name="chk_purchase_orders_total_mxn"),
        UniqueConstraint("tenant_id", "folio", name="uq_purchase_orders_tenant_folio"),
        Index("idx_purchase_orders_tenant_supplier", "tenant_id", "supplier_id"),
        Index("idx_purchase_orders_tenant_status", "tenant_id", "status"),
        Index("idx_purchase_orders_tenant_created_at", "tenant_id", "created_at"),
        {"schema": "inventmx"},
    )

    # Identificador único UUID
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # Identificador del inquilino (Aislamiento RLS)
    tenant_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Identificador del proveedor
    supplier_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.suppliers.id", ondelete="RESTRICT"),
        nullable=False,
    )
    # Almacén de destino para la recepción física
    warehouse_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.warehouses.id", ondelete="RESTRICT"),
        nullable=False,
    )
    # Consecutivo único de orden de compra (ej: OC-00001)
    folio = Column(String(50), nullable=False)
    # Estado actual de la orden
    status = Column(
        Enum(PurchaseOrderStatus, name="purchase_order_status_enum", schema="inventmx"),
        nullable=False,
        default=PurchaseOrderStatus.DRAFT,
    )
    # Subtotal en Pesos Mexicanos ($ MXN)
    subtotal_mxn = Column(Numeric(14, 2), nullable=False, default=Decimal("0.00"))
    # Impuestos en Pesos Mexicanos ($ MXN)
    tax_mxn = Column(Numeric(14, 2), nullable=False, default=Decimal("0.00"))
    # Total en Pesos Mexicanos ($ MXN)
    total_mxn = Column(Numeric(14, 2), nullable=False, default=Decimal("0.00"))
    # Fecha estimada de entrega
    expected_delivery_date = Column(Date, nullable=True)
    # Fecha real de recepción física
    received_date = Column(Date, nullable=True)
    # Folio o número de factura / remisión del proveedor
    invoice_reference = Column(String(100), nullable=True)
    # Observaciones o notas
    notes = Column(Text, nullable=True)
    # Usuario que registró la orden de compra
    created_by_user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.users.id", ondelete="RESTRICT"),
        nullable=False,
    )
    # Marcas de tiempo
    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    # Relaciones ORM
    supplier = relationship("Supplier", back_populates="purchase_orders")
    items = relationship("PurchaseOrderItem", back_populates="purchase_order", cascade="all, delete-orphan")
    account_payable = relationship("AccountPayable", back_populates="purchase_order", uselist=False)


class PurchaseOrderItem(Base):
    """
    Línea de detalle individual de una Orden de Compra (RF-15, RF-17).
    """
    __tablename__ = "purchase_order_items"
    __table_args__ = (
        CheckConstraint("quantity_ordered > 0", name="chk_po_items_quantity_ordered"),
        CheckConstraint("quantity_received >= 0", name="chk_po_items_quantity_received"),
        CheckConstraint("unit_cost_mxn >= 0", name="chk_po_items_unit_cost_mxn"),
        CheckConstraint("subtotal_mxn >= 0", name="chk_po_items_subtotal_mxn"),
        Index("idx_po_items_tenant_order", "tenant_id", "purchase_order_id"),
        Index("idx_po_items_tenant_product", "tenant_id", "product_id"),
        {"schema": "inventmx"},
    )

    # Identificador único UUID
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # Identificador del inquilino (Aislamiento RLS)
    tenant_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Identificador de la orden de compra padre
    purchase_order_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.purchase_orders.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Identificador del producto comprado
    product_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.products.id", ondelete="RESTRICT"),
        nullable=False,
    )
    # Cantidad total ordenada
    quantity_ordered = Column(Numeric(14, 4), nullable=False)
    # Cantidad recibida acumulada
    quantity_received = Column(Numeric(14, 4), nullable=False, default=Decimal("0.0000"))
    # Costo unitario acordado / facturado en Pesos Mexicanos ($ MXN)
    unit_cost_mxn = Column(Numeric(14, 4), nullable=False, default=Decimal("0.0000"))
    # Subtotal del renglón en Pesos Mexicanos ($ MXN)
    subtotal_mxn = Column(Numeric(14, 2), nullable=False, default=Decimal("0.00"))
    # Número de lote asignado por el fabricante
    lot_number = Column(String(50), nullable=True)
    # Fecha de caducidad del lote
    expiry_date = Column(Date, nullable=True)
    # Fecha de registro
    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )

    # Relaciones ORM
    purchase_order = relationship("PurchaseOrder", back_populates="items")
    product = relationship("app.modules.inventory.domain.product.Product")
