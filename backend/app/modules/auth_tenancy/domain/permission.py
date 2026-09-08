import uuid
from typing import List
from sqlalchemy import Column, ForeignKey, String, Table
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database.base import Base, SCHEMA

# Tabla de asociación muchos a muchos: roles <-> permisos en schema inventmx
role_permissions = Table(
    "role_permissions",
    Base.metadata,
    Column(
        "role_id",
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.roles.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "permission_id",
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.permissions.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    schema=SCHEMA,
)


class Permission(Base):
    """
    Catálogo de permisos atómicos del sistema (RBAC).
    Ejemplos: 'inventory.view', 'inventory.edit_price', 'sales.checkout', 'cash.close_session'.
    """
    __tablename__ = "permissions"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    code: Mapped[str] = mapped_column(
        String(100),
        unique=True,
        nullable=False,
        index=True,
    )
    description: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )

    roles: Mapped[List["Role"]] = relationship(
        "Role",
        secondary=role_permissions,
        back_populates="permissions",
    )
