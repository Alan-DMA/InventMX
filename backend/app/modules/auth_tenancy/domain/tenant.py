from decimal import Decimal
import enum
import uuid
from datetime import datetime, timezone
from typing import List, Optional
from sqlalchemy import Boolean, DateTime, Enum, Numeric, String
from sqlalchemy.dialects.postgresql import UUID, ENUM as PG_ENUM
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database.base import Base, SCHEMA


class TenantPlan(str, enum.Enum):
    EMPRENDEDOR = "EMPRENDEDOR"  # $199 MXN / mes
    COMERCIO = "COMERCIO"        # $399 MXN / mes
    CORPORATIVO = "CORPORATIVO"  # $699 MXN / mes


class TenantStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    SOFT_LOCK = "SOFT_LOCK"
    HARD_LOCK = "HARD_LOCK"


class TenantLockReason(str, enum.Enum):
    """Por qué está bloqueado un comercio (Centro de soporte, P17)."""
    NONPAYMENT = "NONPAYMENT"  # Venció sin renovar (ciclo) o bloqueo previo por falta de pago
    ABUSE = "ABUSE"            # Suspensión de soporte: sólo soporte la levanta


class Tenant(Base):
    """
    Entidad raíz del comercio minorista (Tenant) en el SaaS Multi-tenant.
    """
    __tablename__ = "tenants"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        index=True,
    )
    name: Mapped[str] = mapped_column(
        String(150),
        nullable=False,
    )
    slug: Mapped[str] = mapped_column(
        String(100),
        unique=True,
        nullable=False,
        index=True,
    )
    plan_id: Mapped[TenantPlan] = mapped_column(
        PG_ENUM(TenantPlan, name="tenant_plan_enum", schema=SCHEMA, create_type=False),
        default=TenantPlan.EMPRENDEDOR,
        nullable=False,
    )
    status: Mapped[TenantStatus] = mapped_column(
        PG_ENUM(TenantStatus, name="tenant_status_enum", schema=SCHEMA, create_type=False),
        default=TenantStatus.ACTIVE,
        nullable=False,
        index=True,
    )
    rfc: Mapped[Optional[str]] = mapped_column(
        String(13),
        nullable=True,
    )
    legal_name: Mapped[Optional[str]] = mapped_column(
        String(200),
        nullable=True,
    )
    enable_usd_secondary: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
    )
    max_margin_percent: Mapped[Decimal] = mapped_column(
        Numeric(5, 2),
        default=Decimal("40.00"),
        nullable=False,
        doc=(
            "Margen máximo sugerido (%) sobre costo, usado como piso del "
            "'precio máximo sugerido' de un producto mientras no haya "
            "suficiente historial de ventas para estimarlo por elasticidad."
        ),
    )
    # Vigencia prepago (P9–P13): hasta cuándo está pagada la suscripción y de
    # dónde vino ese periodo (TRIAL, COURTESY, MANUAL, GATEWAY, GOOGLE_PLAY).
    # Un comercio nuevo nace con un mes desde su registro.
    paid_until: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    subscription_source: Mapped[Optional[str]] = mapped_column(
        String(20),
        nullable=True,
    )
    # Motivo del bloqueo vigente (`TenantLockReason`); vacío si está activo
    lock_reason: Mapped[Optional[str]] = mapped_column(
        String(20),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Relaciones
    users: Mapped[List["User"]] = relationship(
        "User",
        back_populates="tenant",
        cascade="all, delete-orphan",
    )
