"""
Apartado de Soporte (P23–P25): `/api/v1/support/*`.

- Con sesión: cualquier rol. Exento del bloqueo total (middleware y
  `get_current_user`): una tienda suspendida por abuso tiene que poder escribir.
- `/support/public/*`: el formulario sin sesión (P24).
"""
import uuid
from typing import List

from fastapi import APIRouter, BackgroundTasks, Depends, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import get_db
from app.core.email.sender import send_email_quietly
from app.core.security.deps import get_current_user
from app.modules.auth_tenancy.domain.user import User
from app.modules.platform_admin.security.deps import request_meta
from app.modules.support_cases.schemas import (
    CaseCreate,
    CaseDetail,
    CaseSummary,
    HelpTopicRead,
    MessageCreate,
    PublicCaseAccepted,
    PublicCaseCreate,
    UnreadCount,
)
from app.modules.support_cases.services.cases import PUBLIC_ACCEPTED, CaseService, PublicCaseService

router = APIRouter(prefix="/support", tags=["Soporte (tendero)"])


def _service(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> CaseService:
    return CaseService(db, user)


@router.get("/topics", response_model=List[HelpTopicRead], summary="Temas de ayuda (según el rol)")
async def topics(service: CaseService = Depends(_service)):
    """Ayuda y formulario de cada tema, servidos por el servidor (se editan desde el panel)."""
    return await service.topics()


@router.get("/cases", response_model=List[CaseSummary], summary="Mis casos (el dueño ve los de la tienda)")
async def list_cases(service: CaseService = Depends(_service)):
    return await service.list()


@router.post("/cases", response_model=CaseDetail, status_code=status.HTTP_201_CREATED, summary="Abrir un caso")
async def create_case(data: CaseCreate, service: CaseService = Depends(_service)):
    return await service.create(data)


@router.get("/cases/unread", response_model=UnreadCount, summary="Respuestas de soporte sin abrir (insignia)")
async def unread(service: CaseService = Depends(_service)):
    return UnreadCount(unread=await service.unread_count())


@router.get("/cases/{case_id}", response_model=CaseDetail, summary="Un caso con su conversación")
async def get_case(case_id: uuid.UUID, service: CaseService = Depends(_service)):
    """Abrirlo marca como leída la respuesta de soporte (si es de quien lo abrió)."""
    return await service.detail(case_id)


@router.post("/cases/{case_id}/messages", response_model=CaseDetail, summary="Responder (reabre si estaba resuelto)")
async def reply(case_id: uuid.UUID, data: MessageCreate, service: CaseService = Depends(_service)):
    return await service.reply(case_id, data.body)


@router.post("/cases/{case_id}/resolve", response_model=CaseDetail, summary="Dar el caso por resuelto")
async def resolve(case_id: uuid.UUID, service: CaseService = Depends(_service)):
    return await service.resolve(case_id)


# ── Sin sesión (P24) ───────────────────────────────────────────────────────

@router.get("/public/topics", response_model=List[HelpTopicRead], summary="Temas para quien no puede entrar")
async def public_topics(db: AsyncSession = Depends(get_db)):
    return await PublicCaseService(db).topics()


@router.post(
    "/public/cases",
    response_model=PublicCaseAccepted,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Escribir a soporte sin sesión",
)
async def create_public_case(
    data: PublicCaseCreate,
    request: Request,
    background: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    """
    Responde siempre lo mismo (exista o no el correo, o si se topó el límite de
    3 al día). El acuse con el número del caso llega al correo de contacto.
    """
    meta = request_meta(request)
    receipt = await PublicCaseService(db).create(data, meta.ip_address)
    if receipt is not None:
        background.add_task(send_email_quietly, receipt)
    return PublicCaseAccepted(message=PUBLIC_ACCEPTED)
