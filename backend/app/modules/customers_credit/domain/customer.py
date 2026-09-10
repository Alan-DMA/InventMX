# Importación de marcas temporales y zonas horarias
from datetime import datetime, timezone
# Importación de precisión decimal para montos monetarios en MXN
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de SQLAlchemy
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa de base de datos
from app.core.database.base import Base


class Customer(Base):
    """
    Modelo de Dominio para Clientes y Límites de Crédito en Tienda / Fiado (RF-06, RF-15 / Const. Art. 1.2.6, 7.2).
    Almacena los datos de contacto, RFC, línea de crédito otorgada y saldo deudor acumulado en Pesos Mexicanos.
    """
    # Nombre físico de la tabla en PostgreSQL
    __tablename__ = "customers"
    # Constraints de tabla y esquema
    __table_args__ = (
        CheckConstraint("credit_limit_mxn >= 0", name="chk_customers_credit_limit_non_negative"),
        CheckConstraint("credit_balance_mxn >= 0", name="chk_customers_credit_balance_non_negative"),
        CheckConstraint("credit_days >= 0", name="chk_customers_credit_days_non_negative"),
        {"schema": "inventmx"},
    )

    # Identificador único universal del cliente
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único universal del cliente",
    )

    # Identificador del inquilino / comercio para aislamiento multi-inquilino (RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        doc="Identificador del inquilino propietario",
    )

    # Nombre completo o razón social del cliente
    full_name: Mapped[str] = mapped_column(
        String(150),
        nullable=False,
        doc="Nombre completo o denominación jurídica del cliente",
    )

    # Teléfono de contacto o WhatsApp
    phone: Mapped[Optional[str]] = mapped_column(
        String(30),
        nullable=True,
        doc="Número telefónico de contacto o mensajería WhatsApp",
    )

    # Correo electrónico
    email: Mapped[Optional[str]] = mapped_column(
        String(100),
        nullable=True,
        doc="Correo electrónico para envío de notas o estados de cuenta",
    )

    # Domicilio físico o dirección de entrega
    address: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Dirección física o domicilio fiscal del cliente",
    )

    # Registro Federal de Contribuyentes (RFC) opcional
    rfc: Mapped[Optional[str]] = mapped_column(
        String(13),
        nullable=True,
        doc="RFC del cliente para facturación o identificación",
    )

    # Límite máximo de crédito otorgado en Pesos Mexicanos ($ MXN)
    credit_limit_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        default=Decimal("0.00"),
        doc="Límite máximo de compra a crédito autorizado en MXN",
    )

    # Saldo deudor acumulado actual en Pesos Mexicanos ($ MXN)
    credit_balance_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        default=Decimal("0.00"),
        doc="Saldo pendiente de pago / deuda actual en MXN",
    )

    # Plazo concedido para liquidar créditos en días
    credit_days: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        doc="Días de gracia o plazo de pago pactado con el cliente",
    )

    # Estado de activación del cliente en el sistema
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        doc="Indica si el cliente está habilitado para operar en mostrador",
    )

    # Observaciones o notas sobre el comportamiento crediticio
    notes: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Observaciones generales o historial de crédito del cliente",
    )

    # Marca de tiempo de creación
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Fecha y hora de registro del cliente",
    )

    # Marca de tiempo de última actualización
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
        doc="Fecha y hora de última modificación",
    )

    # Relación uno-a-muchos con el libro mayor de cargos y abonos
    ledger_entries: Mapped[List["CustomerCreditLedger"]] = relationship(
        "CustomerCreditLedger",
        back_populates="customer",
        cascade="all, delete-orphan",
        lazy="selectin",
        doc="Historial de movimientos de crédito (cargos y abonos) del cliente",
    )
