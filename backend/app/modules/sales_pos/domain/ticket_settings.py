# Importación de marcas temporales
from datetime import datetime, timezone
# Importación de tipado estático
from typing import Optional
# Importación de identificadores UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Importación de la clase base declarativa
from app.core.database.base import Base


class TicketSettings(Base):
    """
    Modelo de Dominio para la Configuración de Tickets Térmicos del Comercio (RF-08 / Const. Art. 1.2.8).
    Define la identidad visual, datos fiscales simplificados, mensajes y ancho de papel para la impresión en mostrador.
    """
    # Nombre de la tabla física en PostgreSQL
    __tablename__ = "ticket_settings"
    # Constraints de tabla
    __table_args__ = (
        CheckConstraint("paper_width_mm IN (58, 80)", name="chk_ticket_paper_width"),
        {"schema": "inventmx"},
    )

    # Identificador del inquilino / comercio (Relación 1 a 1 como clave primaria)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventmx.tenants.id", ondelete="CASCADE"),
        primary_key=True,
        doc="Identificador del comercio propietario de la configuración",
    )

    # Nombre comercial de la tienda para el encabezado del ticket
    business_name: Mapped[Optional[str]] = mapped_column(
        String(150),
        nullable=True,
        doc="Nombre comercial o de fantasía que aparece en la cabecera del ticket",
    )

    # Razón social del comercio (opcional para tickets no fiscales)
    legal_name: Mapped[Optional[str]] = mapped_column(
        String(150),
        nullable=True,
        doc="Razón social o denominación jurídica del negocio",
    )

    # Registro Federal de Contribuyentes (RFC) opcional
    rfc: Mapped[Optional[str]] = mapped_column(
        String(13),
        nullable=True,
        doc="RFC del establecimiento comercial para identificación simplificada",
    )

    # Domicilio físico o dirección del establecimiento
    address: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
        doc="Dirección física o sucursal impresa en el ticket",
    )

    # Teléfono de atención o contacto del negocio
    phone: Mapped[Optional[str]] = mapped_column(
        String(30),
        nullable=True,
        doc="Teléfono de contacto o WhatsApp del comercio",
    )

    # Correo electrónico de contacto del establecimiento
    email: Mapped[Optional[str]] = mapped_column(
        String(100),
        nullable=True,
        doc="Correo electrónico impreso en el pie de ticket",
    )

    # Mensaje de agradecimiento o despedida al pie del ticket
    footer_message: Mapped[str] = mapped_column(
        Text,
        nullable=False,
        default="¡Gracias por su compra!",
        doc="Mensaje de cortesía o políticas de cambio al final del ticket",
    )

    # Ancho del papel térmico en milímetros (58mm = 32 columnas, 80mm = 48 columnas)
    paper_width_mm: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=58,
        doc="Ancho físico del rollo térmico soportado por la impresora del POS",
    )

    # Bandera para mostrar u ocultar la leyenda de ahorro total por descuentos
    show_savings: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        doc="Indica si se imprime el bloque de cuánto ahorró el cliente",
    )

    # Bandera para imprimir el nombre del cajero responsable de la venta
    show_cashier_name: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        doc="Indica si se incluye el nombre del cajero en el comprobante",
    )

    # Bandera para desglosar impuestos informativos en el ticket
    show_taxes: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        doc="Indica si se desglosa IVA informativo no-fiscal en el ticket",
    )

    # Estampa de tiempo de última actualización
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
        doc="Fecha y hora de última modificación de los parámetros del ticket",
    )

    # Relación inversa con el Inquilino / Comercio
    tenant: Mapped["Tenant"] = relationship(
        "Tenant",
        doc="Comercio al que pertenece la configuración de tickets",
    )
