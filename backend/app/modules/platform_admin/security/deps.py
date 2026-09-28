"""Dependencias FastAPI del panel: operador autenticado y metadatos de la petición."""
import uuid

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import get_db
from app.core.exceptions.base import UnauthorizedException
from app.modules.platform_admin.domain.operator import PlatformOperator
from app.modules.platform_admin.repositories.audit_repository import RequestMeta
from app.modules.platform_admin.repositories.operator_repository import OperatorRepository
from app.modules.platform_admin.security import tokens

_bearer = HTTPBearer(auto_error=False, scheme_name="PlatformBearer")


async def get_current_operator(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    db: AsyncSession = Depends(get_db),
) -> PlatformOperator:
    """Sólo tokens `platform_access` firmados con la llave de plataforma."""
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise UnauthorizedException("Falta la sesión del panel.")
    payload = tokens.decode(credentials.credentials, tokens.ACCESS)
    operator = await OperatorRepository(db).get_by_id(uuid.UUID(payload["sub"]))
    if operator is None or not operator.is_active or not operator.totp_enabled:
        raise UnauthorizedException("Credenciales de plataforma inválidas.")
    return operator


def request_meta(request: Request) -> RequestMeta:
    forwarded = request.headers.get("X-Forwarded-For", "")
    ip = forwarded.split(",")[0].strip() if forwarded else (request.client.host if request.client else None)
    return RequestMeta(ip_address=ip, user_agent=request.headers.get("User-Agent"))
