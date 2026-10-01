"""
La pestaña de soporte (`main_support.dart`): `/api/v1/support-session`.

Canjear el enlace no lleva token (el enlace es la credencial: de un uso, 10
min). Estado, extender y terminar llevan el token de la sesión. Exentas del
bloqueo por suscripción y de la regla de sólo lectura: son la sesión misma.
"""
from typing import Optional

from fastapi import APIRouter, Depends
from fastapi import status as http_status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import get_db
from app.core.exceptions.base import UnauthorizedException
from app.core.security.jwt import decode_token
from app.modules.platform_admin.repositories.audit_repository import RequestMeta
from app.modules.platform_admin.security.deps import request_meta
from app.modules.platform_admin.services.support_session import (
    OpenedSupportSession,
    SupportSessionStatus,
    TabSupportSession,
)

router = APIRouter(prefix="/support-session", tags=["Sesión de soporte (pestaña)"])
_bearer = HTTPBearer(auto_error=False)


class OpenRequest(BaseModel):
    code: str = Field(..., min_length=10, max_length=100, description="Código del enlace que abrió el panel")


def _tab(meta: RequestMeta = Depends(request_meta), db: AsyncSession = Depends(get_db)) -> TabSupportSession:
    return TabSupportSession(db, meta)


def _support_payload(credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer)) -> dict:
    if credentials is None:
        raise UnauthorizedException("Falta la sesión de soporte.")
    payload = decode_token(credentials.credentials)
    if payload.get("type") != "access" or not payload.get("support_session"):
        raise UnauthorizedException("No es una sesión de soporte.")
    return payload


@router.post("/open", response_model=OpenedSupportSession, summary="Canjear el enlace por la sesión")
async def open_session(data: OpenRequest, tab: TabSupportSession = Depends(_tab)):
    """La primera vez empieza el reloj de 30 min; "Abrir de nuevo" no lo reinicia."""
    return await tab.open_with_code(data.code)


@router.get("", response_model=SupportSessionStatus, summary="Estado de la sesión (para el marco)")
async def session_status(payload: dict = Depends(_support_payload), tab: TabSupportSession = Depends(_tab)):
    return await tab.status(payload)


@router.post("/extend", response_model=OpenedSupportSession, summary="Seguir 30 min más")
async def extend(payload: dict = Depends(_support_payload), tab: TabSupportSession = Depends(_tab)):
    """Con 10 min o menos por delante; nunca más allá del permiso del dueño. Devuelve un token nuevo."""
    return await tab.extend(payload)


@router.post("/end", status_code=http_status.HTTP_204_NO_CONTENT, summary="Terminar desde la pestaña")
async def end(payload: dict = Depends(_support_payload), tab: TabSupportSession = Depends(_tab)):
    await tab.end(payload)
