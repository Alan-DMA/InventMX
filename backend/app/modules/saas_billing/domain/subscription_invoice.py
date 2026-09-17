# Importación de módulos de fecha y hora
from datetime import date, datetime, timezone
# Importación de precisión decimal para montos en moneda nacional MXN
from decimal import Decimal
# Importación de enumeraciones nativas
import enum
# Importación de tipado estático
from typing import Optional
# Importación de identificador único universal
import uuid

# Importación de componentes de SQLAlchemy
from sqlalchemy import (
    Date,
    DateTime,
    Enum as SQLEnum,
    ForeignKey,
    Numeric,
    String,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase Base y el esquema canónico 'public'
from app.core.database.base import Base, SCHEMA
from app.modules.auth_tenancy.domain.tenant import TenantPlan


class SubscriptionInvoiceStatus(str, enum.Enum):
    """
    Estados posibles de una factura de suscripción SaaS mensual.
    """
    PENDING = "PENDING"      # Factura generada pendiente de pago
    PAID = "PAID"            # Factura liquidada exitosamente
    OVERDUE = "OVERDUE"      # Factura con fecha límite vencida (inicia Soft Lock)
    CANCELLED = "CANCELLED"  # Factura cancelada por cambio de plan o anulación administrativa


class SaasPaymentMethod(str, enum.Enum):
    """
    Métodos de pago aceptados para la mensualidad del SaaS en México.
    """
    SPEI = "SPEI"  # Transferencia bancaria directa con CLABE interbancaria personalizada
    OXXO = "OXXO"  # Pago en efectivo en tiendas de conveniencia OXXO con código de barras
    CARD = "CARD"  # Cargo automático o domiciliado con tarjeta de débito/crédito


class SubscriptionInvoice(Base):
    """
    Modelo de Dominio para Facturas de Suscripción SaaS (public.subscription_invoices).
    Representa el cobro periódico mensual del plan contratado por cada Tenant.
    """
    # Nombre físico de la tabla en PostgreSQL
    __tablename__ = "subscription_invoices"
    # Esquema universal de datos
    __table_args__ = {"schema": SCHEMA}

    # Identificador único universal de la factura
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único universal de la factura",
    )

    # Identificador del comercio / tenant que adeuda la factura
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Comercio titular de la factura de suscripción",
    )

    # Plan contratado para el período de cobro
    plan: Mapped[TenantPlan] = mapped_column(
        SQLEnum(
            TenantPlan,
            name="tenant_plan_enum",
            schema=SCHEMA,
            create_type=False,
        ),
        nullable=False,
        doc="Nivel de plan contratado (EMPRENDEDOR, COMERCIO, CORPORATIVO)",
    )

    # Importe total de la factura en Pesos Mexicanos
    amount_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        doc="Importe a pagar en Pesos Mexicanos (MXN)",
    )

    # Método de pago asignado o seleccionado para liquidar la factura
    payment_method: Mapped[SaasPaymentMethod] = mapped_column(
        SQLEnum(
            SaasPaymentMethod,
            name="saas_payment_method_enum",
            schema=SCHEMA,
            create_type=False,
        ),
        nullable=False,
        default=SaasPaymentMethod.SPEI,
        doc="Método de pago establecido para esta factura",
    )

    # Estado actual del ciclo de cobro de la factura
    status: Mapped[SubscriptionInvoiceStatus] = mapped_column(
        SQLEnum(
            SubscriptionInvoiceStatus,
            name="subscription_invoice_status_enum",
            schema=SCHEMA,
            create_type=False,
        ),
        nullable=False,
        default=SubscriptionInvoiceStatus.PENDING,
        index=True,
        doc="Estado actual de la factura de suscripción",
    )

    # Fecha de inicio del ciclo de facturación cubierto
    period_start: Mapped[date] = mapped_column(
        Date,
        nullable=False,
        doc="Fecha inicial del periodo de servicio cubierto",
    )

    # Fecha de fin o vencimiento del ciclo de facturación
    period_end: Mapped[date] = mapped_column(
        Date,
        nullable=False,
        doc="Fecha final de vigencia del periodo de servicio",
    )

    # Referencia de pago alfanumérica única (ej: NX202609150001)
    payment_reference: Mapped[Optional[str]] = mapped_column(
        String(64),
        nullable=True,
        unique=True,
        index=True,
        doc="Referencia única generada para rastreo y conciliación del pago",
    )

    # CLABE interbancaria exclusiva (18 dígitos) para transferencias SPEI vía STP
    clabe: Mapped[Optional[str]] = mapped_column(
        String(18),
        nullable=True,
        doc="CLABE interbancaria única de 18 dígitos para recepción de SPEI",
    )

    # Referencia numérica de 14 dígitos para pago en cajas OXXO Pay
    oxxo_reference: Mapped[Optional[str]] = mapped_column(
        String(20),
        nullable=True,
        doc="Referencia numérica de 14 dígitos para pago en tiendas OXXO",
    )

    # Fecha y hora exacta de confirmación del pago
    paid_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        doc="Estampa de tiempo en la que se confirmó el abono del pago",
    )

    # Fecha y hora de creación de la factura
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Estampa de tiempo de emisión de la factura",
    )

    # Fecha y hora de última actualización del estado
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
        doc="Estampa de tiempo de la última modificación",
    )
