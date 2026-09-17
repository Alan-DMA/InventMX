# Importación de módulos de tiempo
from datetime import datetime
# Importación de tipado
from typing import Any, Dict
# Importación de identificadores únicos UUID
import uuid

# Importación de componentes de SQLAlchemy
from sqlalchemy import (
    Boolean,
    DateTime,
    String,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

# Importación de la clase Base y el esquema canónico 'public'
from app.core.database.base import Base, SCHEMA


class WebhookLog(Base):
    """
    Modelo de Dominio para Bitácora de Notificaciones Webhook (public.saas_webhook_logs).
    Registra payloads entrantes de pasarelas de pago (SPEI STP, OXXO Pay) para garantizar
    idempotencia, trazabilidad de auditoría y evitar cobros duplicados.
    """
    # Nombre físico de la tabla en PostgreSQL
    __tablename__ = "saas_webhook_logs"
    # Esquema universal de datos
    __table_args__ = {"schema": SCHEMA}

    # Identificador único universal del evento de webhook
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único del registro de webhook",
    )

    # Proveedor de la pasarela o institución financiera notificante
    provider: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        doc="Proveedor de pago emisor del webhook (ej: SPEI, OXXO, STP)",
    )

    # Referencia del pago informada en el payload
    reference_id: Mapped[str] = mapped_column(
        String(64),
        nullable=False,
        index=True,
        doc="Referencia alfanumérica del pago reportado",
    )

    # Payload completo recibido en formato JSON estructurado
    payload: Mapped[Dict[str, Any]] = mapped_column(
        JSONB,
        nullable=False,
        doc="Cuerpo original de la petición recibida para auditoría",
    )

    # Indicador de si el webhook fue procesado y conciliado con éxito
    processed: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
        doc="Bandera que indica si el webhook aplicó cambios de saldo o reactivación",
    )

    # Fecha y hora de recepción del webhook
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Estampa de tiempo de recepción del webhook",
    )
