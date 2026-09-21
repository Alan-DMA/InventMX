import uuid
from decimal import Decimal
from typing import Optional
from sqlalchemy import Boolean, Enum as SQLEnum, ForeignKey, Numeric, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database.base import TenantBaseModel, SCHEMA
from app.modules.auth_tenancy.domain.role import Role
from app.modules.auth_tenancy.domain.tenant import Tenant
from app.modules.sales_pos.domain.commission import CommissionType


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
    default_warehouse_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.warehouses.id", ondelete="SET NULL"),
        nullable=True,
        doc="Almacén operativo del usuario — configurable desde su perfil.",
    )
    # Esquema de comisión del empleado (RF-10): el checkout registra un asiento
    # en `sale_commissions` con estos valores cada vez que él cobra una venta.
    # Tasa 0 = no comisiona (valor por defecto para todos, incluido el dueño).
    commission_type: Mapped[CommissionType] = mapped_column(
        SQLEnum(
            CommissionType,
            name="commission_type_enum",
            schema=SCHEMA,
            values_callable=lambda x: [e.value for e in x],
            create_type=False,
        ),
        nullable=False,
        default=CommissionType.PERCENTAGE_SALE,
        server_default=CommissionType.PERCENTAGE_SALE.value,
        doc="Cómo se calcula la comisión: % sobre venta, % sobre utilidad o monto fijo por ticket.",
    )
    commission_rate: Mapped[Decimal] = mapped_column(
        Numeric(5, 2),
        nullable=False,
        default=Decimal("0.00"),
        server_default="0.00",
        doc="Porcentaje (0-100) o monto fijo en $ MXN segun `commission_type`.",
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
