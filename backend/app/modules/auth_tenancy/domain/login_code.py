"""
Código de un solo uso que sustituye a la contraseña (Centro de soporte, P16).

Lo pide el propio usuario ("¿Olvidaste tu contraseña?", `SELF`) o lo genera
soporte tras validar al dueño (`ASSISTED`, P21). En los dos casos llega al
correo registrado y sólo se guarda su hash: ni la base ni el operador lo ven.
Se lee antes de iniciar sesión, sin comercio en contexto, por eso la tabla no
tiene RLS (como `tenants`).
"""
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database.base import SCHEMA, Base


class LoginCodeOrigin:
    SELF = "SELF"
    ASSISTED = "ASSISTED"


class LoginCode(Base):
    __tablename__ = "login_codes"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.users.id", ondelete="CASCADE"), nullable=False
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=False
    )
    code_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    origin: Mapped[str] = mapped_column(String(10), nullable=False)
    created_by_operator_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.platform_operators.id", ondelete="RESTRICT"), nullable=True
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    used_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    invalidated_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    failed_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    def is_usable(self, now: datetime) -> bool:
        return self.used_at is None and self.invalidated_at is None and now < self.expires_at
