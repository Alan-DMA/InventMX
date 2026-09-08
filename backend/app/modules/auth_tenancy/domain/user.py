import uuid
from typing import Optional
from sqlalchemy import Boolean, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database.base import TenantBaseModel, SCHEMA
from app.modules.auth_tenancy.domain.role import Role
from app.modules.auth_tenancy.domain.tenant import Tenant


class User(TenantBaseModel):
    """
    Usuario del sistema perteneciente a un Tenant específico.
    Protegido por políticas de Row-Level Security (RLS).
    """
    __tablename__ = "users"
    __table_args__ = {"schema": SCHEMA}

    email: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        index=True,
    )
    hashed_password: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )
    full_name: Mapped[str] = mapped_column(
        String(150),
        nullable=False,
    )
    role_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.roles.id"),
        nullable=False,
        index=True,
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )

    # Relaciones
    tenant: Mapped[Tenant] = relationship(
        "Tenant",
        back_populates="users",
    )
    role: Mapped[Role] = relationship(
        "Role",
        back_populates="users",
        lazy="selectin",
    )
