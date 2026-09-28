"""
Bitácora de la plataforma: quién hizo qué, cuándo, en qué comercio y por qué.

De sólo anexar: un trigger de la base rechaza UPDATE, DELETE y TRUNCATE
(migración 0025). Cada renglón guarda el hash del anterior, así que alterar la
tabla por fuera de la aplicación rompe la cadena y `verify_chain` lo detecta.
"""
# Importación de módulos de fecha, UUID y tipado
import uuid
from datetime import datetime
from typing import Any, Dict, Optional

# Importación de tipos de SQLAlchemy
from sqlalchemy import BigInteger, DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database.base import SCHEMA, Base


class AuditAction:
    """Acciones registradas. Las de `TENANT_VISIBLE` las ve el Dueño (P8)."""
    LOGIN_SUCCEEDED = "LOGIN_SUCCEEDED"
    LOGIN_FAILED = "LOGIN_FAILED"
    TOTP_FAILED = "TOTP_FAILED"
    TOTP_ENROLLED = "TOTP_ENROLLED"
    RECOVERY_CODE_USED = "RECOVERY_CODE_USED"
    OPERATOR_LOCKED = "OPERATOR_LOCKED"
    TENANT_VIEWED = "TENANT_VIEWED"
    PAYMENT_CONFIRMED = "PAYMENT_CONFIRMED"
    STATUS_CHANGED = "STATUS_CHANGED"
    PLAN_CHANGED = "PLAN_CHANGED"
    COURTESY_GRANTED = "COURTESY_GRANTED"
    # Sólo desde el script de servidor `scripts/platform_operator.py`
    OPERATOR_CREATED = "OPERATOR_CREATED"
    OPERATOR_DEACTIVATED = "OPERATOR_DEACTIVATED"
    TOTP_RESET = "TOTP_RESET"

    # Lo que soporte cambió en la suscripción de un comercio: su Dueño lo ve
    # en "Actividad de soporte", con el motivo (P8, transparencia).
    TENANT_VISIBLE = (PAYMENT_CONFIRMED, STATUS_CHANGED, PLAN_CHANGED, COURTESY_GRANTED)


class PlatformAuditLog(Base):
    __tablename__ = "platform_audit_log"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    operator_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.platform_operators.id", ondelete="RESTRICT"),
        nullable=True,
    )
    action: Mapped[str] = mapped_column(String(60), nullable=False)
    target_tenant_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), nullable=True)
    target_type: Mapped[Optional[str]] = mapped_column(String(40), nullable=True)
    target_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    details: Mapped[Dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    ip_address: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    user_agent: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    prev_hash: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    row_hash: Mapped[str] = mapped_column(String(64), nullable=False)
