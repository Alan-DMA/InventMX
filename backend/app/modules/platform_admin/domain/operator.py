"""
Operadores de la plataforma (Alan y Eduardo) y sus códigos de recuperación.

No heredan de `TenantBaseModel`: no pertenecen a ningún comercio. Se crean sólo
con `scripts/create_platform_operator.py`; no hay registro por API.
"""
# Importación de módulos de fecha, UUID y tipado
import uuid
from datetime import datetime
from typing import Optional

# Importación de tipos de SQLAlchemy
from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database.base import SCHEMA, Base


class PlatformOperator(Base):
    """Persona que opera la plataforma. Entra con contraseña + TOTP."""
    __tablename__ = "platform_operators"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    full_name: Mapped[str] = mapped_column(String(150), nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    # Secreto TOTP cifrado con Fernet; existe desde el primer acceso, pero sólo
    # cuenta como vinculado cuando `totp_enabled_at` tiene fecha.
    totp_secret_encrypted: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    totp_enabled_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    # Último paso de 30 s aceptado: impide repetir un código ya usado
    totp_last_step: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True)
    failed_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    locked_until: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    last_login_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    @property
    def totp_enabled(self) -> bool:
        return self.totp_enabled_at is not None


class PlatformRecoveryCode(Base):
    """Código de recuperación de un solo uso (se guarda su SHA-256)."""
    __tablename__ = "platform_recovery_codes"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    operator_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.platform_operators.id", ondelete="CASCADE"),
        nullable=False,
    )
    code_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    used_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
