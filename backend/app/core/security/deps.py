# Importación de UUID para validación tipada de identificadores
import uuid
# Importación de tipos estáticos y Callable para decorators/factories
from typing import Callable, Optional
# Importación de constructs de inyección de dependencias de FastAPI
from fastapi import Depends
# Importación del esquema de seguridad HTTP Bearer
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
# Importación de la sesión asíncrona de SQLAlchemy
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de utilidades de sesión de base de datos e inyector RLS
from app.core.database.session import get_db, set_tenant_context
# Importación de excepciones personalizadas de negocio
from app.core.exceptions.base import (
    ForbiddenException,
    TenantLockedException,
    UnauthorizedException,
)
# Importación del decodificador y validador de JWT
from app.core.security.jwt import decode_token
# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.tenant import TenantStatus
from app.modules.auth_tenancy.domain.user import User
# Importación del repositorio de usuarios
from app.modules.auth_tenancy.repositories.user_repository import UserRepository

# Instanciación del esquema de seguridad HTTP Bearer (auto_error=False para control granular)
security = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> User:
    """
    Extrae el JWT Bearer Token, valida la identidad del usuario,
    verifica el estado del Tenant e inyecta de forma segura el contexto RLS
    en la sesión de base de datos activa.
    """
    # 1. Comprobar presencia del encabezado Authorization
    if not credentials or not credentials.credentials:
        raise UnauthorizedException("No se proporcionó token de autorización Bearer.")

    # 2. Decodificar y validar el JWT token
    token = credentials.credentials
    payload = decode_token(token)

    # 3. Validar que el token sea de tipo 'access' y no 'refresh'
    if payload.get("type") != "access":
        raise UnauthorizedException("El token proporcionado no es un token de acceso válido.")

    # 4. Extraer el subject (UUID del usuario)
    user_id_str = payload.get("sub")
    if not user_id_str:
        raise UnauthorizedException("Token inválido: falta identificador de usuario.")

    try:
        user_uuid = uuid.UUID(user_id_str)
    except ValueError:
        raise UnauthorizedException("Identificador de usuario inválido en token.")

    # 5. Consultar el usuario en la base de datos con rol y permisos cargados
    user_repo = UserRepository(db)
    user = await user_repo.get_by_id(user_uuid)

    if not user:
        raise UnauthorizedException("El usuario asociado a este token no existe.")

    # 6. Validar que la cuenta del usuario no esté desactivada
    if not user.is_active:
        raise UnauthorizedException("La cuenta de usuario se encuentra inactiva.")

    # 7. Validar existencia del comercio asociado
    tenant = user.tenant
    if not tenant:
        raise UnauthorizedException("El comercio asociado al usuario no existe.")

    # 8. Inyección estricta de contexto RLS en PostgreSQL para la petición en curso
    await set_tenant_context(db, user.tenant_id)

    return user


async def require_active_tenant(current_user: User = Depends(get_current_user)) -> User:
    """
    Verifica que el Tenant no se encuentre en HARD_LOCK (morosidad total).
    Const. Art. 6.3.
    """
    if current_user.tenant.status == TenantStatus.HARD_LOCK:
        raise TenantLockedException(
            message="El servicio se encuentra suspendido por falta de pago. Accede al portal de reactivación.",
            lock_type="HARD_LOCK",
        )
    return current_user


async def require_unlocked_tenant(current_user: User = Depends(get_current_user)) -> User:
    """
    Verifica que el Tenant no se encuentre ni en SOFT_LOCK ni en HARD_LOCK.
    Usado para operaciones de escritura (crear ventas, compras, movimientos de caja).
    Const. Art. 6.3.
    """
    if current_user.tenant.status == TenantStatus.HARD_LOCK:
        raise TenantLockedException(
            message="Servicio suspendido por falta de pago.",
            lock_type="HARD_LOCK",
        )
    if current_user.tenant.status == TenantStatus.SOFT_LOCK:
        raise TenantLockedException(
            message="Comercio en periodo de gracia (Solo Lectura). Regulariza tu pago para registrar nuevas operaciones.",
            lock_type="SOFT_LOCK",
        )
    return current_user


def require_permission(permission_code: str) -> Callable:
    """
    Dependencia de seguridad RBAC granular (Doc. Maestro Sec. 9.2).
    Verifica que el rol del usuario contenga el código de permiso requerido.
    """
    async def permission_checker(current_user: User = Depends(get_current_user)) -> User:
        # El rol OWNER siempre tiene todos los permisos por definición sagrada
        if current_user.role and current_user.role.name == "OWNER":
            return current_user

        # Validar existencia de permisos en el rol asignado
        if not current_user.role or not current_user.role.permissions:
            raise ForbiddenException(f"No tienes el permiso requerido: '{permission_code}'.")

        # Obtener el conjunto de códigos de permiso del usuario
        user_permission_codes = {p.code for p in current_user.role.permissions}
        if permission_code not in user_permission_codes:
            raise ForbiddenException(f"Permiso denegado: se requiere '{permission_code}'.")

        return current_user

    return permission_checker
