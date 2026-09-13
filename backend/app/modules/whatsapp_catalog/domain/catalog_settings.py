# Importación del módulo datetime para marcas temporales con zona horaria
from datetime import datetime
# Importación del módulo decimal para operaciones monetarias exactas
from decimal import Decimal
# Importación de tipado estático
from typing import Optional
# Importación de identificadores únicos universales UUID
import uuid
# Importación de constructs de SQLAlchemy
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa y esquema del sistema
from app.core.database.base import Base, SCHEMA


class CatalogSettings(Base):
    """
    Modelo de Dominio para la configuración del Catálogo Digital de WhatsApp Web (RF-26 / Const. Art. 7.4).
    Gestiona preferencias de pedido, número de WhatsApp, pedidos mínimos y costos de envío en $ MXN.
    """
    # Nombre de la tabla física en PostgreSQL
    __tablename__ = "catalog_settings"
    # Configuración de constraints de esquema y validaciones financieras
    __table_args__ = (
        # Validación de no negatividad para pedido mínimo en MXN
        CheckConstraint("min_order_amount_mxn >= 0", name="chk_catalog_min_order_mxn_non_negative"),
        # Validación de no negatividad para costo de entrega en MXN
        CheckConstraint("delivery_fee_mxn >= 0", name="chk_catalog_delivery_fee_mxn_non_negative"),
        # Esquema específico de inventario
        {"schema": SCHEMA},
    )

    # Identificador único UUID de la configuración
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único universal del registro de configuración",
    )

    # Identificador único del comercio dueño (Aislamiento Multi-Tenant)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
        index=True,
        doc="Clave foránea hacia el comercio (Tenant)",
    )

    # Bandera maestra para activar o suspender el catálogo público
    is_catalog_enabled: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
        doc="Indica si el catálogo web público está disponible para clientes finales",
    )

    # Número de WhatsApp oficial para recibir pedidos
    whatsapp_number: Mapped[Optional[str]] = mapped_column(
        String(20),
        nullable=True,
        doc="Número de teléfono celular con código de país para enlaces wa.me",
    )

    # Mensaje de bienvenida personalizado
    welcome_message: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Texto de bienvenida o descripción de la tienda visible en la cabecera",
    )

    # Monto mínimo de compra en Pesos Mexicanos ($ MXN)
    min_order_amount_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Importe mínimo requerido en $ MXN para permitir enviar un pedido",
    )

    # Costo de envío a domicilio en Pesos Mexicanos ($ MXN)
    delivery_fee_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Tarifa estándar de flete o envío a domicilio en $ MXN",
    )

    # Habilitación de entrega a domicilio
    delivery_enabled: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
        doc="Permite a los clientes seleccionar entrega a domicilio",
    )

    # Habilitación de recogida en tienda física
    pickup_enabled: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
        doc="Permite a los clientes seleccionar recoger en sucursal",
    )

    # Horario comercial de atención
    business_hours: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Texto informativo sobre días y horarios de servicio",
    )

    # Fecha y hora de creación
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Estampa de tiempo de creación de la configuración",
    )

    # Fecha y hora de última modificación
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
        doc="Estampa de tiempo de última actualización",
    )
