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
from app.modules.sales_pos.domain.payment import PaymentMethod


class AccountPayableStatus(str, enum.Enum):
    """
    Estados financieros de una cuenta por pagar a proveedores.
    """
    PENDING = "PENDING"
    PARTIALLY_PAID = "PARTIALLY_PAID"
    PAID = "PAID"
    OVERDUE = "OVERDUE"
    CANCELLED = "CANCELLED"


class AccountPayable(Base):
    """
    Cuenta por Pagar (CxP) a Proveedor en Pesos Mexicanos ($ MXN) (RF-16).
    """
    __tablename__ = "accounts_payable"
    __table_args__ = (
        CheckConstraint("total_mxn >= 0", name="chk_accounts_payable_total_mxn"),
        CheckConstraint("amount_paid_mxn >= 0", name="chk_accounts_payable_amount_paid_mxn"),
        UniqueConstraint("tenant_id", "folio", name="uq_accounts_payable_tenant_folio"),
        Index("idx_ap_tenant_supplier", "tenant_id", "supplier_id"),
        Index("idx_ap_tenant_status", "tenant_id", "status"),
        Index("idx_ap_tenant_due_date", "tenant_id", "due_date"),
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
    # Identificador del proveedor acreedor
    supplier_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.suppliers.id", ondelete="RESTRICT"),
        nullable=False,
    )
    # Identificador de la orden de compra que originó la deuda (opcional)
    purchase_order_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.purchase_orders.id", ondelete="SET NULL"),
        nullable=True,
    )
    # Consecutivo único de la cuenta por pagar (ej: CXP-00001)
    folio = Column(String(50), nullable=False)
    # Monto total de la deuda en Pesos Mexicanos ($ MXN)
    total_mxn = Column(Numeric(14, 2), nullable=False)
    # Monto acumulado abonado / pagado en Pesos Mexicanos ($ MXN)
    amount_paid_mxn = Column(Numeric(14, 2), nullable=False, default=Decimal("0.00"))
    # Estado de la deuda (PENDING, PARTIALLY_PAID, PAID, OVERDUE, CANCELLED)
    status = Column(
        Enum(AccountPayableStatus, name="account_payable_status_enum", schema="inventmx"),
        nullable=False,
        default=AccountPayableStatus.PENDING,
    )
    # Fecha límite de vencimiento de pago
    due_date = Column(Date, nullable=False)
    # Número de factura o remisión del proveedor
    invoice_reference = Column(String(100), nullable=True)
    # Notas adicionales
    notes = Column(Text, nullable=True)
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
    supplier = relationship("Supplier", back_populates="accounts_payable")
    purchase_order = relationship("PurchaseOrder", back_populates="account_payable")
    payments = relationship("SupplierPaymentLedger", back_populates="account_payable", cascade="all, delete-orphan")


class SupplierPaymentLedger(Base):
    """
    Registro individual de un abono o pago a una Cuenta por Pagar de Proveedor (RF-16).
    """
    __tablename__ = "supplier_payment_ledger"
    __table_args__ = (
        CheckConstraint("amount_paid_mxn > 0", name="chk_supplier_payment_amount_mxn"),
        Index("idx_supplier_payment_tenant_ap", "tenant_id", "account_payable_id"),
        Index("idx_supplier_payment_tenant_supplier", "tenant_id", "supplier_id"),
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
    # Identificador de la cuenta por pagar liquidada/abonada
    account_payable_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.accounts_payable.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Identificador del proveedor beneficiario
    supplier_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.suppliers.id", ondelete="RESTRICT"),
        nullable=False,
    )
    # Monto pagado en Pesos Mexicanos ($ MXN)
    amount_paid_mxn = Column(Numeric(14, 2), nullable=False)
    # Método de pago utilizado (CASH_MXN, SPEI, CODI, CARD_TPV, OTHER)
    payment_method = Column(
        Enum(PaymentMethod, name="payment_method_enum", schema="inventmx"),
        nullable=False,
        default=PaymentMethod.CASH_MXN,
    )
    # Folio de transferencia SPEI, cheque o voucher
    reference_code = Column(String(100), nullable=True)
    # Fecha del pago
    payment_date = Column(Date, nullable=False, default=date.today)
    # Notas u observaciones del pago
    notes = Column(Text, nullable=True)
    # Usuario que registró el egreso de dinero
    created_by_user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.users.id", ondelete="RESTRICT"),
        nullable=False,
    )
    # Fecha y hora exacta de registro
    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )

    # Relaciones ORM
    account_payable = relationship("AccountPayable", back_populates="payments")
    supplier = relationship("Supplier")
