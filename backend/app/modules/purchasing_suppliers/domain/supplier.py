# Importación de enumeraciones de Python
import enum
# Importación de precisión decimal para Pesos Mexicanos
from decimal import Decimal
# Importación de marcas de tiempo y fechas
from datetime import datetime, timezone
# Importación de identificadores únicos universales
import uuid
# Importación de SQLAlchemy
from sqlalchemy import (
    CheckConstraint,
    Column,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

# Importación de la base declarativa de modelos
from app.core.database.base import Base


class SupplierStatus(str, enum.Enum):
    """
    Estados operativos de un proveedor comercial en el sistema.
    """
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"


class Supplier(Base):
    """
    Entidad Proveedor para control de compras y cuentas por pagar (RF-15, RF-16).
    """
    __tablename__ = "suppliers"
    __table_args__ = (
        CheckConstraint("credit_days >= 0", name="chk_suppliers_credit_days"),
        CheckConstraint("credit_limit_mxn >= 0", name="chk_suppliers_credit_limit_mxn"),
        Index("idx_suppliers_tenant_name", "tenant_id", "name"),
        Index("idx_suppliers_tenant_rfc", "tenant_id", "rfc"),
        {"schema": "inventmx"},
    )

    # Identificador único UUID
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # Identificador del inquilino (Aislamiento Multi-tenant RLS)
    tenant_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Nombre de la empresa proveedora o razón social
    name = Column(String(150), nullable=False)
    # RFC fiscal del proveedor (opcional)
    rfc = Column(String(13), nullable=True)
    # Teléfono o WhatsApp de contacto
    phone = Column(String(30), nullable=True)
    # Correo electrónico
    email = Column(String(100), nullable=True)
    # Dirección física o fiscal
    address = Column(Text, nullable=True)
    # Días de crédito otorgados por el proveedor
    credit_days = Column(Integer, nullable=False, default=0)
    # Límite máximo de crédito en Pesos Mexicanos ($ MXN)
    credit_limit_mxn = Column(Numeric(14, 2), nullable=False, default=Decimal("0.00"))
    # Estado activo o inactivo
    status = Column(
        Enum(SupplierStatus, name="supplier_status_enum", schema="inventmx"),
        nullable=False,
        default=SupplierStatus.ACTIVE,
    )
    # Notas u observaciones
    notes = Column(Text, nullable=True)
    # Marcas de tiempo
    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    # Relaciones ORM
    purchase_orders = relationship("PurchaseOrder", back_populates="supplier", cascade="all, delete-orphan")
    accounts_payable = relationship("AccountPayable", back_populates="supplier", cascade="all, delete-orphan")
