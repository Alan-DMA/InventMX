"""
Soporte dentro de la app, estilo Steam (P23–P25, migración 0028).

- `HelpTopic`: ayuda de un tema + la definición de su formulario. Contenido de la
  plataforma, servido por el servidor y editable desde el panel.
- `SupportCase`: lo que llega a soporte. Con comercio (desde la app, con RLS) o
  sin él (formulario sin sesión, P24: sólo lo ve el panel).
- `SupportCaseMessage`: el hilo del caso.
"""
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Identity, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database.base import SCHEMA, Base


class TopicAudience:
    ALL = "ALL"              # cualquiera con sesión
    OWNER = "OWNER"          # sólo el dueño (suscripción, sus datos)
    ANONYMOUS = "ANONYMOUS"  # formulario sin sesión (P24)


class CaseStatus:
    WAITING_SUPPORT = "WAITING_SUPPORT"  # le toca a soporte
    ANSWERED = "ANSWERED"                # soporte respondió: le toca al tendero
    RESOLVED = "RESOLVED"


class CaseChannel:
    APP = "APP"
    PUBLIC = "PUBLIC"


class AuthorKind:
    REQUESTER = "REQUESTER"
    SUPPORT = "SUPPORT"


class HelpTopic(Base):
    __tablename__ = "help_topics"
    __table_args__ = {"schema": SCHEMA}

    key: Mapped[str] = mapped_column(String(40), primary_key=True)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    summary: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    body: Mapped[str] = mapped_column(Text, nullable=False, default="")
    actions: Mapped[List[Dict[str, Any]]] = mapped_column(JSONB, nullable=False, default=list)
    form_fields: Mapped[List[Dict[str, Any]]] = mapped_column(JSONB, nullable=False, default=list)
    audience: Mapped[str] = mapped_column(String(10), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=100)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.platform_operators.id", ondelete="RESTRICT"), nullable=True
    )


class SupportCase(Base):
    __tablename__ = "support_cases"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    number: Mapped[int] = mapped_column(BigInteger, Identity(start=1001), unique=True)
    tenant_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=True
    )
    author_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.users.id", ondelete="SET NULL"), nullable=True
    )
    channel: Mapped[str] = mapped_column(String(10), nullable=False)
    topic_key: Mapped[str] = mapped_column(String(40), nullable=False)
    topic_title: Mapped[str] = mapped_column(String(120), nullable=False)
    details: Mapped[Dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default=CaseStatus.WAITING_SUPPORT)
    contact_email: Mapped[str] = mapped_column(String(255), nullable=False)
    contact_name: Mapped[Optional[str]] = mapped_column(String(150), nullable=True)
    claimed_store_name: Mapped[Optional[str]] = mapped_column(String(150), nullable=True)
    suggested_tenant_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), nullable=True)
    requester_ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    requester_unread: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    last_message_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class SupportCaseMessage(Base):
    __tablename__ = "support_case_messages"
    __table_args__ = {"schema": SCHEMA}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    case_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.support_cases.id", ondelete="CASCADE"), nullable=False
    )
    tenant_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"), nullable=True
    )
    author_kind: Mapped[str] = mapped_column(String(10), nullable=False)
    author_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.users.id", ondelete="SET NULL"), nullable=True
    )
    operator_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.platform_operators.id", ondelete="RESTRICT"), nullable=True
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
