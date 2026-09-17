from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text
from sqlalchemy.orm import selectinload
import jwt
from uuid import UUID

from app.core.database import get_db
from app.core.config import settings
from app.core.rls import set_current_tenant
from app.core.saas_config import NEXUS_FOUNDER_EMAILS
from app.models.models import User, Tenant, Role

# Dependencias propias del módulo SaaS (Tarea 14.2).
#
# `get_current_user` (deps.py) aplica la máquina de estados de morosidad y
# responde 403 a TODO cuando el tenant está en HARD_LOCK — incluidas las rutas
# que le permitirían pagar. Las rutas de suscripción necesitan una variante
# que autentique sin bloquear; se duplica aquí la carga del token para no
# modificar el archivo de Alan.

reusable_oauth2 = HTTPBearer()


async def get_current_user_allow_locked(
    http_auth: HTTPAuthorizationCredentials = Depends(reusable_oauth2),
    db: AsyncSession = Depends(get_db),
) -> User:
    """Valida el JWT y carga el usuario (con rol y permisos) sin aplicar Soft/Hard Lock."""
    token = http_auth.credentials
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("type") != "access":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token de acceso inválido.",
            )
        user_id = payload.get("sub")
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sesión expirada o token inválido.",
        )

    # Búsqueda global (sin contexto de tenant) — igual que deps.get_current_user
    await db.execute(text("SELECT set_config('app.current_tenant', '', false)"))
    result = await db.execute(
        select(User)
        .options(selectinload(User.role).selectinload(Role.permissions))
        .where(User.id == UUID(user_id))
    )
    user = result.scalars().first()
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario inactivo o no encontrado.",
        )

    set_current_tenant(user.tenant_id)
    await db.execute(
        text("SELECT set_config('app.current_tenant', :tenant_id, false)"),
        {"tenant_id": str(user.tenant_id)},
    )
    return user


def user_permissions(user: User) -> list[str]:
    """Nombres de permisos del rol del usuario (vacío si no tiene rol)."""
    if user.role is None:
        return []
    return sorted(p.name for p in user.role.permissions)


def is_founder(user: User) -> bool:
    """D7: permiso `saas.manage` y, si NEXUS_FOUNDER_EMAILS está definido, correo en la lista."""
    if "saas.manage" not in user_permissions(user):
        return False
    if NEXUS_FOUNDER_EMAILS and user.email.lower() not in NEXUS_FOUNDER_EMAILS:
        return False
    return True


async def require_saas_manage(
    user: User = Depends(get_current_user_allow_locked),
    db: AsyncSession = Depends(get_db),
) -> User:
    """Puerta del panel de fundadores. Limpia el contexto de tenant: las consultas son globales."""
    if not is_founder(user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "SAAS_FOUNDER_ONLY",
                "message": "Este panel es exclusivo de los fundadores de Nexus.",
            },
        )
    set_current_tenant(None)
    await db.execute(text("SELECT set_config('app.current_tenant', '', false)"))
    return user


async def get_user_tenant(db: AsyncSession, user: User) -> Tenant:
    result = await db.execute(select(Tenant).where(Tenant.id == user.tenant_id))
    tenant = result.scalars().first()
    if not tenant:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tenant no encontrado.")
    return tenant
