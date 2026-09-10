# Importación de marcas temporales
from datetime import datetime, timezone
# Importación de precisión decimal
from decimal import Decimal
# Importación de enumeraciones estándar
import enum
# Importación de tipado estático
from typing import Optional, TYPE_CHECKING
# Importación de identificadores UUID
import uuid
# Importación de SQLAlchemy
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

# Importación de la clase base declarativa
from app.core.database.base import Base

if TYPE_CHECKING:
    from app.modules.sales_pos.domain.sale import Sale


class PaymentMethod(str, enum.Enum):
    """
    Métodos de pago oficiales soportados en el Punto de Venta (RF-13 / Const. Art. 3.2).
    Desacoplamiento contable: el sistema actúa como registro contable sin validar fondos bancarios automáticamente.
    """
    CASH_MXN = "CASH_MXN"      # Pago en efectivo en Pesos Mexicanos
    SPEI = "SPEI"              # Transferencia electrónica interbancaria SPEI / CLABE
    CODI = "CODI"              # Plataforma digital de cobro CoDi / Dimo Banxico
    CARD_TPV = "CARD_TPV"      # Tarjeta débito/crédito vía Terminal Punto de Venta (Clip, MP, Zettle)
    OTHER = "OTHER"            # Otros medios de pago autorizados


class SalePayment(Base):
    """
    Modelo de Dominio para el Registro Contable de Pagos POS (inventmx.sale_payments).
    Representa cada abono o método de pago liquidado en una nota de venta (RF-13, RF-14).
    """
    # Nombre de la tabla en base de datos
    __tablename__ = "sale_payments"
    # Configuración de constraints y esquema
    __table_args__ = (
        CheckConstraint("amount_paid_mxn > 0", name="chk_sale_payments_amount_positive"),
        CheckConstraint("change_returned_mxn >= 0", name="chk_sale_payments_change_non_negative"),
        {"schema": "inventmx"},
    )

    # Identificador único UUID del pago
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del registro de pago",
    )

    # Identificador del inquilino (Tenant) para aislamiento multi-tenant RLS
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="ID del inquilino propietario de la transacción",
    )

    # Identificador de la venta cabecera a la que pertenece el pago
    sale_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.sales.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="ID de la venta liquidada",
    )

    # Método de pago utilizado
    payment_method: Mapped[PaymentMethod] = mapped_column(
        SQLEnum(PaymentMethod, name="payment_method_enum", schema="inventmx", native_enum=True),
        nullable=False,
        index=True,
        doc="Método contable de pago recibido",
    )

    # Importe monetario entregado por el cliente en Pesos Mexicanos ($ MXN)
    amount_paid_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Monto monetario entregado por el cliente en $ MXN",
    )

    # Cambio o vuelto devuelto al cliente en Pesos Mexicanos ($ MXN)
    change_returned_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Cambio entregado en efectivo al cliente",
    )

    # Código de referencia opcional (Folio SPEI, autorización voucher TPV o folio CoDi)
    reference_code: Mapped[Optional[str]] = mapped_column(
        String(100),
        nullable=True,
        doc="Referencia externa o folio de autorización bancaria",
    )

    # Notas u observaciones adicionales del cajero
    notes: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Observaciones del cobro",
    )

    # Estampa de tiempo de registro del pago
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=func.now(),
        nullable=False,
        index=True,
        doc="Fecha y hora de registro contable del pago",
    )

    # Relación inversa con la venta cabecera
    sale: Mapped["Sale"] = relationship("Sale", back_populates="payments")
