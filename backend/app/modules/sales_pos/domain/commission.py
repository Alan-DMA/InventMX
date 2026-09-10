# Importación de marcas temporales
from datetime import datetime, timezone
# Importación de precisión decimal
from decimal import Decimal
# Importación de enumeraciones estándar
import enum
# Importación de tipado estático
from typing import Optional
# Importación de identificadores UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Enum as SQLEnum,
    ForeignKey,
    Numeric,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa
from app.core.database.base import Base


class CommissionType(str, enum.Enum):
    """
    Tipos de esquemas de comisiones dinámicas soportados por el POS (RF-10 / Const. Art. 8.2).
    """
    # Comisión calculada como un porcentaje fijo sobre el total bruto de la venta
    PERCENTAGE_SALE = "PERCENTAGE_SALE"
    # Comisión calculada como un porcentaje sobre la utilidad bruta generada (Total - Costo Histórico)
    PERCENTAGE_PROFIT = "PERCENTAGE_PROFIT"
    # Comisión fija en $ MXN por cada venta concretada
    FIXED_PER_SALE = "FIXED_PER_SALE"


class SaleCommission(Base):
    """
    Modelo de Dominio para el Asiento Inmutable de Comisiones por Venta (inventmx.sale_commissions).
    Garantiza transparencia en los incentivos laborales de cajeros y vendedores (RF-10 / Const. Art. 8.2).
    """
    # Nombre de la tabla física en PostgreSQL
    __tablename__ = "sale_commissions"
    # Constraints de tabla
    __table_args__ = (
        CheckConstraint("commission_rate >= 0", name="chk_sale_commissions_rate_non_negative"),
        CheckConstraint("commission_amount_mxn >= 0", name="chk_sale_commissions_amount_non_negative"),
        {"schema": "inventmx"},
    )

    # Identificador único UUID del asiento de comisión
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del asiento de comisión",
    )

    # Identificador del comercio propietario (Aislamiento Multi-tenant RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el comercio dueño de la comisión",
    )

    # Identificador de la venta que originó la comisión
    sale_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.sales.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia la venta comisionable",
    )

    # Identificador del usuario beneficiario (cajero o vendedor asignado)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el empleado acreedor de la comisión",
    )

    # Tipo de esquema de comisión aplicado
    commission_type: Mapped[CommissionType] = mapped_column(
        SQLEnum(
            CommissionType,
            name="commission_type_enum",
            schema="inventmx",
            values_callable=lambda x: [e.value for e in x],
        ),
        nullable=False,
        default=CommissionType.PERCENTAGE_SALE,
        doc="Mecanismo de cálculo utilizado para determinar la comisión",
    )

    # Tasa o porcentaje aplicado (ej: 5.00 para 5%)
    commission_rate: Mapped[Decimal] = mapped_column(
        Numeric(5, 2),
        nullable=False,
        default=Decimal("0.00"),
        doc="Tasa porcentual o tarifa fija aplicada",
    )

    # Base monetaria sobre la que se calculó la comisión en $ MXN
    base_amount_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        default=Decimal("0.00"),
        doc="Monto base ($ MXN) de la venta o utilidad sujeta a comisión",
    )

    # Importe monetario neto de comisión devengada en Pesos Mexicanos ($ MXN)
    commission_amount_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        default=Decimal("0.00"),
        doc="Importe liquidable a favor del empleado en $ MXN",
    )

    # Bandera que indica si la comisión ya fue pagada o liquidada al empleado en nómina
    is_settled: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        doc="Indica si la comisión ya fue dispersada o liquidada en corte",
    )

    # Fecha y hora en que se liquidó la comisión
    settled_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        doc="Estampa de tiempo de pago de la comisión al empleado",
    )

    # Fecha y hora de devengo inmutable
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Fecha y hora de congelamiento de la comisión al cobrar la venta",
    )

    # Relación inversa con la Venta
    sale: Mapped["Sale"] = relationship(
        "Sale",
        back_populates="commissions",
        doc="Venta asociada a este registro de comisión",
    )

    # Relación con el Usuario beneficiario
    user: Mapped["User"] = relationship(
        "User",
        doc="Empleado acreedor de la comisión",
    )
