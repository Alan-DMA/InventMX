"""Esquemas del apartado de Soporte (tendero, formulario sin sesión y panel)."""
import uuid
from datetime import datetime
from typing import Dict, List, Literal, Optional

from pydantic import BaseModel, EmailStr, Field, field_validator

DESCRIPTION_FIELD = Field(..., min_length=10, max_length=2000, description="Cuéntanos qué pasó")


def _strip(value: str) -> str:
    return value.strip()


# ── Temas de ayuda ─────────────────────────────────────────────────────────

class FormField(BaseModel):
    key: str = Field(..., min_length=1, max_length=40, pattern=r"^[a-z][a-z0-9_]*$")
    label: str = Field(..., min_length=1, max_length=120)
    type: Literal["text", "textarea", "select"]
    required: bool = False
    options: List[str] = Field(default_factory=list, description="Sólo para `select`")


class TopicAction(BaseModel):
    """Botón de la ayuda que lleva a una pantalla de la app; la app ignora `target` que no conozca."""
    label: str = Field(..., min_length=1, max_length=60)
    target: str = Field(..., min_length=1, max_length=40)


class HelpTopicRead(BaseModel):
    key: str
    title: str
    summary: str
    body: str = Field(..., description="Párrafos separados por línea en blanco; '• ' al inicio = viñeta")
    actions: List[TopicAction]
    form_fields: List[FormField]


# ── Casos (tendero) ────────────────────────────────────────────────────────

class CaseCreate(BaseModel):
    topic_key: str = Field(..., max_length=40)
    answers: Dict[str, str] = Field(default_factory=dict, description="Respuestas del formulario del tema, por `key`")
    description: str = DESCRIPTION_FIELD

    _clean = field_validator("description")(_strip)


class PublicCaseCreate(CaseCreate):
    """Formulario sin sesión (P24): quien no puede entrar."""
    account_email: EmailStr = Field(..., description="Correo con el que entra (o entraba) a Nexus")
    store_name: str = Field(..., min_length=2, max_length=150)
    contact_email: EmailStr = Field(..., description="Dónde le respondemos (puede ser otro si perdió el de la cuenta)")
    contact_name: Optional[str] = Field(None, max_length=150)
    # Campo trampa: invisible para personas; un bot lo llena
    website: Optional[str] = Field(None, max_length=200)


class MessageCreate(BaseModel):
    body: str = Field(..., min_length=1, max_length=2000)

    _clean = field_validator("body")(_strip)


class Answer(BaseModel):
    key: str
    label: str
    value: str


class MessageRead(BaseModel):
    id: uuid.UUID
    author_kind: Literal["REQUESTER", "SUPPORT"]
    author_name: str
    body: str
    created_at: datetime


CaseStatusValue = Literal["WAITING_SUPPORT", "ANSWERED", "RESOLVED"]


class CaseSummary(BaseModel):
    id: uuid.UUID
    number: int
    topic_key: str
    topic_title: str
    status: CaseStatusValue
    unread: bool = Field(..., description="Soporte respondió y no se ha abierto")
    author_name: Optional[str] = None
    is_mine: bool
    created_at: datetime
    last_message_at: datetime


class CaseDetail(CaseSummary):
    answers: List[Answer]
    messages: List[MessageRead]


class UnreadCount(BaseModel):
    unread: int


class PublicCaseAccepted(BaseModel):
    message: str


# ── Panel ──────────────────────────────────────────────────────────────────

class DeskCaseSummary(BaseModel):
    id: uuid.UUID
    number: int
    channel: Literal["APP", "PUBLIC"]
    tenant_id: Optional[uuid.UUID] = None
    tenant_name: Optional[str] = None
    topic_key: str
    topic_title: str
    status: CaseStatusValue
    contact_email: str
    contact_name: Optional[str] = None
    claimed_store_name: Optional[str] = None
    suggested_tenant_id: Optional[uuid.UUID] = Field(
        None, description="Sin sesión: comercio cuyo correo coincide con el que dio (para validar, P21)",
    )
    suggested_tenant_name: Optional[str] = None
    created_at: datetime
    last_message_at: datetime


class DeskCasePage(BaseModel):
    items: List[DeskCaseSummary]
    total: int


class DeskCaseDetail(DeskCaseSummary):
    answers: List[Answer]
    messages: List[MessageRead]


class DeskReply(BaseModel):
    body: str = Field(..., min_length=1, max_length=2000, description="Lo lee el tendero tal cual")
    resolve: bool = Field(False, description="Responder y dar el caso por resuelto")

    _clean = field_validator("body")(_strip)


class DeskStatusChange(BaseModel):
    status: CaseStatusValue


class HelpTopicAdmin(HelpTopicRead):
    audience: Literal["ALL", "OWNER", "ANONYMOUS"]
    sort_order: int
    is_active: bool
    updated_at: datetime


class HelpTopicUpsert(BaseModel):
    title: str = Field(..., min_length=2, max_length=120)
    summary: str = Field("", max_length=200)
    body: str = Field("", max_length=5000)
    actions: List[TopicAction] = Field(default_factory=list, max_length=4)
    form_fields: List[FormField] = Field(default_factory=list, max_length=8)
    audience: Literal["ALL", "OWNER", "ANONYMOUS"]
    sort_order: int = Field(100, ge=0, le=1000)
    is_active: bool = True
    reason: str = Field(..., min_length=10, max_length=500, description="Por qué se cambia (bitácora)")

    @field_validator("form_fields")
    @classmethod
    def _selects_have_options(cls, fields: List[FormField]) -> List[FormField]:
        keys = [f.key for f in fields]
        if len(keys) != len(set(keys)):
            raise ValueError("Dos campos del formulario tienen la misma clave.")
        for f in fields:
            if f.type == "select" and len(f.options) < 2:
                raise ValueError(f"El campo '{f.key}' es de opciones y necesita al menos dos.")
        return fields
