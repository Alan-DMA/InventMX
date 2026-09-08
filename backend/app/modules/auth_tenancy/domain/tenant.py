import enum
import uuid
from datetime import datetime, timezone
from typing import List, Optional
from sqlalchemy import Boolean, DateTime, Enum, String
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
