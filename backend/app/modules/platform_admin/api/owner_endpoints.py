"""
Lo que el dueño de la tienda controla del soporte, desde su app:
`/api/v1/support-access` — conceder, ver y retirar el acceso de soporte (P2/P18).
Sólo el Dueño: un empleado no decide quién entra a los datos de su patrón.
"""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import get_db
from app.core.security.deps import require_owner
from app.modules.auth_tenancy.domain.user import User
from app.modules.platform_admin.repositories.audit_repository import RequestMeta
from app.modules.platform_admin.security.deps import request_meta
from app.modules.platform_admin.services.support_access import (
    GrantRequest,
    SupportAccessService,
    SupportAccessStatus,
)

router = APIRouter(prefix="/support-access", tags=["Acceso de soporte (dueño)"])


def _service(
    owner: User = Depends(require_owner),
    meta: RequestMeta = Depends(request_meta),
    db: AsyncSession = Depends(get_db),
) -> SupportAccessService:
    return SupportAccessService(db, owner, meta)


@router.get("", response_model=SupportAccessStatus, summary="¿Soporte puede entrar a mi tienda?")
async def status(service: SupportAccessService = Depends(_service)):
    return await service.status()


@router.post("", response_model=SupportAccessStatus, summary="Conceder acceso de soporte (sólo lectura)")
async def grant(data: GrantRequest, service: SupportAccessService = Depends(_service)):
    """Por 1, 24 o 72 horas; reemplaza a una concesión vigente."""
    return await service.grant(data.hours)


@router.delete("", response_model=SupportAccessStatus, summary="Retirar el acceso de soporte")
async def revoke(service: SupportAccessService = Depends(_service)):
    return await service.revoke()
