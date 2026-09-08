# Importación del módulo UUID para identificación única
import uuid
# Importación de datetime y timedelta para cálculo de expiración en UTC
from datetime import datetime, timedelta, timezone
# Importación de tipos estáticos
from typing import Any, Dict, Optional, Union
# Importación de la librería PyJWT para cifrado de tokens
import jwt

# Importación de la configuración centralizada de la aplicación
from app.core.config.settings import settings
# Importación de excepción personalizada de autenticación
from app.core.exceptions.base import UnauthorizedException


def create_access_token(
    subject: Union[str, uuid.UUID],
    tenant_id: Union[str, uuid.UUID],
    role: str,
    tenant_status: str = "ACTIVE",
    expires_delta: Optional[timedelta] = None,
) -> str:
    """
    Genera un JWT Access Token firmado criptográficamente con algoritmo HS256.
    Incluye claims de usuario, tenant_id, rol y estado de suscripción del tenant.
    """
    # Obtener marca de tiempo actual en UTC
    now = datetime.now(timezone.utc)
    # Calcular fecha y hora de expiración
    expire = now + (expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES))
    
    # Construcción del diccionario de claims del payload
    to_encode: Dict[str, Any] = {
        "sub": str(subject),                         # Identificador del usuario (Subject)
        "tenant_id": str(tenant_id),                 # Identificador del comercio (RLS Context)
        "role": role,                               # Nombre del rol asignado (RBAC)
        "tenant_status": tenant_status,             # Estado de morosidad (ACTIVE, SOFT_LOCK, HARD_LOCK)
        "iat": now,                                 # Timestamp de emisión
        "exp": expire,                              # Timestamp de expiración
        "type": "access",                           # Tipo de token
    }
    # Codificar y firmar el token con la clave secreta
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(
    subject: Union[str, uuid.UUID],
    tenant_id: Union[str, uuid.UUID],
    expires_delta: Optional[timedelta] = None,
) -> str:
    """
    Genera un JWT Refresh Token de larga duración para renovación de sesiones.
    """
    now = datetime.now(timezone.utc)
    expire = now + (expires_delta or timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS))
    
    to_encode: Dict[str, Any] = {
        "sub": str(subject),
        "tenant_id": str(tenant_id),
        "iat": now,
        "exp": expire,
        "type": "refresh",
    }
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> Dict[str, Any]:
    """
    Decodifica y valida la firma de un token JWT.
    Lanza UnauthorizedException si el token está expirado, alterado o es ilegible.
    """
    try:
        # Decodificación y validación de firma
        payload = jwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )
        return payload
    except jwt.ExpiredSignatureError:
        # Expiración temporal del token
        raise UnauthorizedException("El token ha expirado. Por favor inicia sesión nuevamente.")
    except jwt.PyJWTError:
        # Error criptográfico o payload corrupto
        raise UnauthorizedException("Token de autenticación inválido o alterado.")
