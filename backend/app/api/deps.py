from fastapi import Depends, HTTPException, status, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text
import jwt
from uuid import UUID

from app.core.database import get_db
from app.core.config import settings
from app.core.rls import set_current_tenant
from app.models.models import User, Tenant

# Utilidad de FastAPI para extraer la cabecera Bearer Token
reusable_oauth2 = HTTPBearer()

async def get_current_user(
    request: Request,
    http_auth: HTTPAuthorizationCredentials = Depends(reusable_oauth2),
    db: AsyncSession = Depends(get_db)
) -> User:
    """
    Dependency para validar el token JWT, cargar el usuario, inyectar el tenant_id 
    en el contexto RLS de Postgres y verificar el estado de la suscripción (Soft/Hard Lock).
    """
    token = http_auth.credentials
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("type") != "access":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token de acceso inválido."
            )
        user_id = payload.get("sub")
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sesión expirada o token inválido."
        )

    # 1. Bypass RLS temporalmente para buscar el usuario por su ID global
    await db.execute(text("SELECT set_config('app.current_tenant', '', false)"))
    
    user_query = select(User).where(User.id == UUID(user_id))
    user_result = await db.execute(user_query)
    user = user_result.scalars().first()

    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario inactivo o no encontrado."
        )

    # 2. Consultar Tenant para validar morosidad (Art. VI, Sección 6.3)
    tenant_query = select(Tenant).where(Tenant.id == user.tenant_id)
    tenant_result = await db.execute(tenant_query)
    tenant = tenant_result.scalars().first()

    if not tenant:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tenant no encontrado."
        )

    # 3. Lógica del Ciclo de Vida de Suscripción (Soft Lock / Hard Lock)
    status_sub = tenant.subscription_status
    
    if status_sub == "HARD_LOCK":
        # Bloqueo total. Solo permite ver pantalla de pago.
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "TENANT_HARD_LOCK",
                "message": "Suscripción suspendida por falta de pago. Por favor contacte a soporte o realice el pago."
            }
        )
    elif status_sub == "SOFT_LOCK":
        # Bloquea creación de ventas y compras (métodos de escritura), pero permite GET.
        if request.method in ["POST", "PUT", "DELETE", "PATCH"]:
            # Permitir únicamente la ruta de pago si existiera, lo demás bloqueado
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": "TENANT_SOFT_LOCK",
                    "message": "Suscripción vencida (Soft Lock). Acceso de solo lectura. Regularice su pago para habilitar la escritura."
                }
            )

    # 4. Establecer el RLS en el ContextVar de Python (para SQLAlchemy)
    set_current_tenant(user.tenant_id)
    
    # 5. Establecer el RLS físicamente en la conexión actual de Postgres
    await db.execute(
        text("SELECT set_config('app.current_tenant', :tenant_id, false)"),
        {"tenant_id": str(user.tenant_id)}
    )

    return user
