"""
Tokens del panel de plataforma.

Firmados con `PLATFORM_JWT_SECRET` (no con la llave de los comercios) y con
audiencia `nexus-platform`: un token de comercio no se decodifica aquí y uno de
plataforma no se decodifica en `get_current_user` de los comercios. Sin
refresh: al vencer (2 h) se vuelve a entrar con contraseña y TOTP.

Dos tipos:
- `platform_challenge` (5 min): contraseña correcta, falta el segundo factor.
- `platform_access`: sesión del panel.
"""
# Importación de módulos de fecha y tipado
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

# Importación de PyJWT
import jwt

# Importación de configuración y excepciones
from app.core.config.settings import settings
from app.core.exceptions.base import UnauthorizedException

AUDIENCE = "nexus-platform"
ALGORITHM = "HS256"
ACCESS = "platform_access"
CHALLENGE = "platform_challenge"

# Propósitos de un reto: vincular TOTP por primera vez o verificarlo
PURPOSE_ENROLL = "enroll"
PURPOSE_VERIFY = "verify"


def _encode(claims: Dict[str, Any], minutes: int) -> str:
    now = datetime.now(timezone.utc)
    payload = {**claims, "aud": AUDIENCE, "iat": now, "exp": now + timedelta(minutes=minutes)}
    return jwt.encode(payload, settings.PLATFORM_JWT_SECRET, algorithm=ALGORITHM)


def create_access_token(operator_id: uuid.UUID) -> str:
    return _encode(
        {"sub": str(operator_id), "type": ACCESS},
        settings.PLATFORM_TOKEN_EXPIRE_MINUTES,
    )


def create_challenge_token(operator_id: uuid.UUID, purpose: str) -> str:
    return _encode(
        {"sub": str(operator_id), "type": CHALLENGE, "purpose": purpose},
        settings.PLATFORM_CHALLENGE_EXPIRE_MINUTES,
    )


def decode(token: str, expected_type: str) -> Dict[str, Any]:
    """Decodifica exigiendo firma, audiencia, vigencia y tipo; 401 si algo falla."""
    try:
        payload = jwt.decode(
            token,
            settings.PLATFORM_JWT_SECRET,
            algorithms=[ALGORITHM],
            audience=AUDIENCE,
            options={"require": ["exp", "iat", "sub", "aud"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise UnauthorizedException("La sesión del panel expiró. Vuelve a entrar.") from exc
    except jwt.PyJWTError as exc:
        raise UnauthorizedException("Credenciales de plataforma inválidas.") from exc
    if payload.get("type") != expected_type:
        raise UnauthorizedException("Credenciales de plataforma inválidas.")
    return payload
