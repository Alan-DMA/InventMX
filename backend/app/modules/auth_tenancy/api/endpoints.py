from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database.session import get_db
from app.core.security.deps import get_current_user
from app.modules.auth_tenancy.domain.user import User
from app.modules.auth_tenancy.schemas.token import (
    RefreshTokenRequest,
    RegisterTenantRequest,
    TokenResponse,
)
from app.modules.auth_tenancy.schemas.user import UserLogin, UserRead
from app.modules.auth_tenancy.services.auth_service import AuthService

router = APIRouter(prefix="/auth", tags=["Autenticación y Tenancy"])


@router.post(
    "/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar nuevo comercio (Tenant) y usuario dueño (Owner)",
)
async def register(
    data: RegisterTenantRequest,
    db: AsyncSession = Depends(get_db),
):
    """
    Crea el comercio (Tenant) bajo el plan Emprendedor por defecto y
    la cuenta de usuario administrador inicial (Owner) de forma atómica.
    """
    service = AuthService(db)
    return await service.register_tenant_and_owner(data)


@router.post(
    "/login",
    response_model=TokenResponse,
    status_code=status.HTTP_200_OK,
    summary="Iniciar sesión en el sistema",
)
async def login(
    login_data: UserLogin,
    db: AsyncSession = Depends(get_db),
):
    """Valida credenciales de usuario y genera Access Token + Refresh Token."""
    service = AuthService(db)
    return await service.authenticate_user(login_data)


@router.post(
    "/refresh",
    response_model=TokenResponse,
    status_code=status.HTTP_200_OK,
    summary="Refrescar sesión con Refresh Token",
)
async def refresh_token(
    data: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db),
):
    """Genera un nuevo Access Token a partir de un Refresh Token vigente."""
    service = AuthService(db)
    return await service.refresh_access_token(data.refresh_token)


@router.get(
    "/me",
    response_model=UserRead,
    status_code=status.HTTP_200_OK,
    summary="Obtener perfil del usuario autenticado",
)
async def get_me(current_user: User = Depends(get_current_user)):
    """Retorna la información del usuario autenticado, su rol y permisos."""
    return current_user
