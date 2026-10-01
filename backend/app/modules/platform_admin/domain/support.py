"""
Registros del Centro de soporte (migración 0027).

- `PlatformExportJob`: exportación de los datos de un comercio al correo de su
  dueño (P18). El panel sólo ve el estado; nunca el archivo.
- `PlatformApprovalRequest`: acción de dos personas (P4). Sin FK al comercio:
  la solicitud sobrevive a la eliminación que aprueba y guarda su nombre.
- `SupportAccessGrant`: el dueño concede acceso de soporte por un tiempo
  (P2/P18). Es del comercio: con RLS.
- `SupportSession` (migración 0029, P37–P39): un operador ve la tienda en sólo
  lectura usando esa concesión. Con RLS del comercio.
"""
import uuid
from datetime import datetime
from typing import List, Optional

from sqlalchemy import BigInteger, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database.base import SCHEMA, Base


class ExportStatus:
    PENDING = "PENDING"
    SENT = "SENT"
    FAILED = "FAILED"


class ApprovalKind:
    TENANT_DELETION = "TENANT_DELETION"


class ApprovalStatus:
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    CANCELLED = "CANCELLED"


class PlatformExportJob(Base):
    __tablename__ = "platform_export_jobs"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=False
    )
    requested_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.platform_operators.id", ondelete="RESTRICT"), nullable=False
    )
    status: Mapped[str] = mapped_column(String(10), nullable=False, default=ExportStatus.PENDING)
    error: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    size_bytes: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    finished_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)


class PlatformApprovalRequest(Base):
    __tablename__ = "platform_approval_requests"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    kind: Mapped[str] = mapped_column(String(30), nullable=False)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    tenant_name: Mapped[str] = mapped_column(String(150), nullable=False)
    requested_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.platform_operators.id", ondelete="RESTRICT"), nullable=False
    )
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(10), nullable=False, default=ApprovalStatus.PENDING)
    decided_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.platform_operators.id", ondelete="RESTRICT"), nullable=True
    )
    decision_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    decided_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class SupportAccessGrant(Base):
    __tablename__ = "support_access_grants"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=False
    )
    granted_by_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.users.id", ondelete="CASCADE"), nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    def is_active(self, now: datetime) -> bool:
        return self.revoked_at is None and now < self.expires_at


class SessionEndReason:
    """Por qué terminó una sesión de soporte (el dueño lo lee en palabras)."""
    OPERATOR = "OPERATOR"                # el operador pulsó "Terminar"
    SIGNED_OUT = "SIGNED_OUT"            # el operador salió del panel
    EXPIRED = "EXPIRED"                  # se acabaron los 30 min (o la extensión)
    GRANT_ENDED = "GRANT_ENDED"          # el dueño retiró el acceso o venció
    NOT_OPENED = "NOT_OPENED"            # el enlace venció sin abrirse
    OPERATOR_INACTIVE = "OPERATOR_INACTIVE"


class SupportSession(Base):
    __tablename__ = "support_sessions"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=False
    )
    grant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.support_access_grants.id", ondelete="CASCADE"), nullable=False
    )
    operator_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.platform_operators.id", ondelete="RESTRICT"), nullable=False
    )
    # El dueño que concedió: la sesión ve lo que él ve
    acting_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.users.id", ondelete="CASCADE"), nullable=False
    )
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    case_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.support_cases.id", ondelete="SET NULL"), nullable=True
    )
    link_hash: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    link_expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    opened_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    extensions: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    sections: Mapped[List[str]] = mapped_column(JSONB, nullable=False, default=list)
    ended_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    end_reason: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    def is_open(self, now: datetime) -> bool:
        """Vigente: sin terminar y, si ya se abrió, dentro de su tiempo; si no, con enlace vigente."""
        if self.ended_at is not None:
            return False
        if self.opened_at is None:
            return self.link_expires_at is not None and now < self.link_expires_at
        return self.expires_at is not None and now < self.expires_at
