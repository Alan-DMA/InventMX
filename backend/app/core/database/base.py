import uuid
from datetime import datetime, timezone
from sqlalchemy import DateTime, ForeignKey, MetaData
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

SCHEMA = "inventmx"

# Metadata con schema por defecto 'inventmx'
metadata_obj = MetaData(schema=SCHEMA)


class Base(DeclarativeBase):
    """Base declarativa para todos los modelos del sistema en schema inventmx."""
    metadata = metadata_obj


class TenantBaseModel(Base):
    """
    Clase abstracta para entidades multi-tenant con Row-Level Security (RLS).
    Todas las tablas que hereden de esta clase asumen la presencia de tenant_id indexado.
    """
    __abstract__ = True

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        index=True,
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
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
