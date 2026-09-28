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
    # Cobro manual y bloqueos de la Fase 1: retirados de la API (P19). Se
    # conservan para que el historial ya escrito se siga leyendo.
    PAYMENT_CONFIRMED = "PAYMENT_CONFIRMED"
    STATUS_CHANGED = "STATUS_CHANGED"
    PLAN_CHANGED = "PLAN_CHANGED"
    COURTESY_GRANTED = "COURTESY_GRANTED"
    # Hecho por el ciclo automático (operador vacío = "Sistema")
    SUBSCRIPTION_SUSPENDED = "SUBSCRIPTION_SUSPENDED"
    # Centro de soporte (Sep 2026)
    ASSISTED_RECOVERY_SENT = "ASSISTED_RECOVERY_SENT"
    DAYS_GIFTED = "DAYS_GIFTED"
    ABUSE_SUSPENDED = "ABUSE_SUSPENDED"
    ABUSE_LIFTED = "ABUSE_LIFTED"
    DATA_EXPORT_REQUESTED = "DATA_EXPORT_REQUESTED"
    DATA_EXPORT_SENT = "DATA_EXPORT_SENT"        # sistema: el archivo salió al correo del dueño
    DATA_EXPORT_FAILED = "DATA_EXPORT_FAILED"    # sistema
    TENANT_DELETION_REQUESTED = "TENANT_DELETION_REQUESTED"
    TENANT_DELETION_CANCELLED = "TENANT_DELETION_CANCELLED"
    TENANT_DELETED = "TENANT_DELETED"            # lo registra quien dio la segunda aprobación
    # Lo hace el dueño desde su app (operador vacío); aquí para el feed
    SUPPORT_ACCESS_GRANTED = "SUPPORT_ACCESS_GRANTED"
    SUPPORT_ACCESS_REVOKED = "SUPPORT_ACCESS_REVOKED"
    # Sólo desde el script de servidor `scripts/platform_operator.py`
    OPERATOR_CREATED = "OPERATOR_CREATED"
    OPERATOR_DEACTIVATED = "OPERATOR_DEACTIVATED"
    TOTP_RESET = "TOTP_RESET"

    # Lo que soporte hizo en la cuenta de un comercio: su Dueño lo ve en
    # "Actividad de soporte", con el motivo (P8, transparencia).
    TENANT_VISIBLE = (
        PAYMENT_CONFIRMED, STATUS_CHANGED, PLAN_CHANGED, COURTESY_GRANTED, SUBSCRIPTION_SUSPENDED,
        ASSISTED_RECOVERY_SENT, DAYS_GIFTED, ABUSE_SUSPENDED, ABUSE_LIFTED,
        DATA_EXPORT_REQUESTED, DATA_EXPORT_SENT, TENANT_DELETION_REQUESTED, TENANT_DELETION_CANCELLED,
    )

    # Ruido que no entra en "Lo que pasó" del feed (sí en la bitácora completa)
    FEED_NOISE = (TENANT_VIEWED, LOGIN_SUCCEEDED, TOTP_ENROLLED, RECOVERY_CODE_USED)


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
