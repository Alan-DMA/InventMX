import uuid
from typing import List, Optional
from sqlalchemy import ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database.base import Base, SCHEMA
from app.modules.auth_tenancy.domain.permission import Permission, role_permissions


class Role(Base):
    """
    Roles del sistema (OWNER, ADMIN, CASHIER, WAREHOUSE).
    Pueden ser roles globales del sistema o personalizados por tenant.
    """
    __tablename__ = "roles"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    tenant_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    name: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        index=True,
    )
    description: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )

    permissions: Mapped[List[Permission]] = relationship(
        "Permission",
        secondary=role_permissions,
        back_populates="roles",
        lazy="selectin",
    )
    users: Mapped[List["User"]] = relationship(
        "User",
        back_populates="role",
    )
