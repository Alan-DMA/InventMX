# Importación de marcas temporales y zonas horarias
from datetime import datetime, timezone
# Importación de precisión decimal
from decimal import Decimal
# Importación de enumeraciones nativas
from enum import Enum
# Importación de tipado estático
from typing import Optional
# Importación de UUID
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
from app.modules.sales_pos.domain.payment import PaymentMethod


class LedgerEntryType(str, Enum):
    """
    Tipos de Asientos en el Libro Mayor de Crédito de Clientes (CxC).
    """
    # Cargo por compra a crédito / fiado en POS (incrementa deuda)
    CHARGE = "CHARGE"
    # Abono o pago recibido del cliente (reduce deuda)
    PAYMENT = "PAYMENT"
    # Ajuste manual autorizado por supervisor
    ADJUSTMENT = "ADJUSTMENT"


class CustomerCreditLedger(Base):
    """
    Modelo de Dominio para el Libro Mayor de Crédito de Clientes (RF-15 / Const. Art. 7.2).
    Registra de forma inmutable cada cargo por venta, abono recibido o ajuste con saldo anterior y posterior.
    """
    # Nombre físico de la tabla en PostgreSQL
    __tablename__ = "customer_credit_ledger"
    # Constraints de tabla y esquema
    __table_args__ = (
        CheckConstraint("amount_mxn > 0", name="chk_credit_ledger_amount_positive"),
        CheckConstraint("previous_balance_mxn >= 0", name="chk_credit_ledger_prev_balance_non_neg"),
        CheckConstraint("resulting_balance_mxn >= 0", name="chk_credit_ledger_res_balance_non_neg"),
        {"schema": "inventmx"},
    )

    # Identificador único del asiento de crédito
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del asiento contable de crédito",
    )

    # Identificador del inquilino para aislamiento multi-tenant (RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        doc="Identificador del inquilino propietario",
    )

    # Identificador del cliente titular de la cuenta corriente
    customer_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.customers.id", ondelete="CASCADE"),
        nullable=False,
        doc="Identificador del cliente asociado",
    )

    # Identificador de la nota de venta vinculada (opcional en caso de abono general)
    sale_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.sales.id", ondelete="SET NULL"),
        nullable=True,
        doc="Identificador de la venta asociada al cargo o liquidación",
    )

    # Tipo de asiento (CHARGE, PAYMENT, ADJUSTMENT)
    entry_type: Mapped[LedgerEntryType] = mapped_column(
        SQLEnum(
            LedgerEntryType,
            name="ledger_entry_type_enum",
            schema="inventmx",
            native_enum=True,
            values_callable=lambda obj: [e.value for e in obj],
        ),
        nullable=False,
        doc="Tipo de movimiento en la cuenta del cliente",
    )

    # Monto del movimiento en Pesos Mexicanos (siempre > 0)
    amount_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Monto monetario de la operación en $ MXN",
    )

    # Saldo deudor antes de la operación en Pesos Mexicanos
    previous_balance_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Saldo que adeudaba el cliente antes del movimiento en $ MXN",
    )

    # Saldo deudor resultante después de la operación en Pesos Mexicanos
    resulting_balance_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Saldo que adeuda el cliente después del movimiento en $ MXN",
    )

    # Método de pago utilizado en caso de abono (Efectivo, SPEI, Tarjeta, etc.)
    payment_method: Mapped[Optional[PaymentMethod]] = mapped_column(
        SQLEnum(
            PaymentMethod,
            name="payment_method_enum",
            schema="inventmx",
            native_enum=True,
            values_callable=lambda obj: [e.value for e in obj],
        ),
        nullable=True,
        doc="Método de pago del abono",
    )

    # Folio bancario o código de referencia del comprobante
    reference_code: Mapped[Optional[str]] = mapped_column(
        String(100),
        nullable=True,
        doc="Código de rastreo SPEI, folio de voucher o cheque",
    )

    # Observaciones adicionales
    notes: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Notas o justificación del asiento de crédito",
    )

    # Usuario cajero o supervisor que registró la transacción
    created_by_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.users.id", ondelete="RESTRICT"),
        nullable=False,
        doc="Usuario responsable de asentar el movimiento",
    )

    # Marca de tiempo inmutable de creación
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Fecha y hora de registro del asiento",
    )

    # Relación inversa con el Cliente
    customer: Mapped["Customer"] = relationship(
        "Customer",
        back_populates="ledger_entries",
        doc="Cliente titular de la cuenta",
    )
