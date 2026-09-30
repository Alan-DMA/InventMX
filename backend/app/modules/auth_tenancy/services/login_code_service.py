"""
Códigos de un solo uso que sustituyen a la contraseña (Centro de soporte, P16).

- Formato `XXXX-XXXX` sobre un alfabeto sin caracteres que se confunden (0/O,
  1/I/L): se dicta y se teclea en el teléfono sin errores. 32⁸ ≈ 10¹² combinaciones
  y 5 intentos por código: adivinarlo no es un camino.
- Sólo se guarda un HMAC con `SECRET_KEY`; el código en claro sólo existe en el
  correo. Pedir uno nuevo invalida los anteriores del mismo usuario.
- La recuperación automática responde siempre lo mismo (exista o no el correo)
  y se limita a `LOGIN_CODE_MAX_REQUESTS_PER_HOUR` por usuario, en silencio.
"""
import hashlib
import hmac
import logging
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config.settings import settings
from app.core.email.sender import EmailMessage
from app.core.email.templates import login_code_email
from app.modules.auth_tenancy.domain.login_code import LoginCode, LoginCodeOrigin
from app.modules.auth_tenancy.domain.user import User
from app.modules.auth_tenancy.repositories.user_repository import UserRepository

logger = logging.getLogger(__name__)

ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
LOGIN_CODE_REJECTED = "Correo o código incorrectos, o el código ya venció."


def _normalize(code: str) -> str:
    return code.replace("-", "").replace(" ", "").strip().upper()


def hash_login_code(code: str) -> str:
    return hmac.new(
        settings.SECRET_KEY.encode("utf-8"), _normalize(code).encode("utf-8"), hashlib.sha256
    ).hexdigest()


def new_login_code() -> str:
    raw = "".join(secrets.choice(ALPHABET) for _ in range(8))
    return f"{raw[:4]}-{raw[4:]}"


def mask_email(email: str) -> str:
    """'donachuy@tienda.mx' → 'do•••••y@tienda.mx': suficiente para que el operador confirme, no para leerlo."""
    local, _, domain = email.partition("@")
    if len(local) <= 3:
        return f"{local[:1]}•••@{domain}"
    return f"{local[:2]}{'•' * (len(local) - 3)}{local[-1]}@{domain}"


class LoginCodeService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def issue(
        self,
        user: User,
        origin: str,
        operator_id: Optional[uuid.UUID] = None,
        now: Optional[datetime] = None,
    ) -> Tuple[str, datetime]:
        """Invalida los códigos vigentes del usuario y crea uno. Devuelve el código en claro para el correo."""
        now = now or datetime.now(timezone.utc)
        await self.invalidate_all(user.id, now)
        ttl = (
            timedelta(hours=settings.LOGIN_CODE_ASSISTED_HOURS)
            if origin == LoginCodeOrigin.ASSISTED
            else timedelta(minutes=settings.LOGIN_CODE_SELF_MINUTES)
        )
        code = new_login_code()
        row = LoginCode(
            user_id=user.id,
            tenant_id=user.tenant_id,
            code_hash=hash_login_code(code),
            origin=origin,
            created_by_operator_id=operator_id,
            expires_at=now + ttl,
        )
        self.db.add(row)
        await self.db.flush()
        return code, row.expires_at

    async def invalidate_all(self, user_id: uuid.UUID, now: Optional[datetime] = None) -> None:
        await self.db.execute(
            update(LoginCode)
            .where(LoginCode.user_id == user_id, LoginCode.used_at.is_(None), LoginCode.invalidated_at.is_(None))
            .values(invalidated_at=now or datetime.now(timezone.utc))
        )

    async def consume(self, user: User, code: str, now: Optional[datetime] = None) -> bool:
        """
        Marca el código como usado si coincide con el vigente. Un fallo suma un
        intento; al quinto el código deja de servir. Confirma su propio cambio.
        """
        now = now or datetime.now(timezone.utc)
        current = (await self.db.execute(
            select(LoginCode)
            .where(
                LoginCode.user_id == user.id,
                LoginCode.used_at.is_(None),
                LoginCode.invalidated_at.is_(None),
                LoginCode.expires_at > now,
            )
            .order_by(LoginCode.created_at.desc())
            .limit(1)
        )).scalar_one_or_none()
        if current is None:
            return False
        if not hmac.compare_digest(current.code_hash, hash_login_code(code)):
            current.failed_attempts += 1
            if current.failed_attempts >= settings.LOGIN_CODE_MAX_ATTEMPTS:
                current.invalidated_at = now
            await self.db.commit()
            return False
        current.used_at = now
        await self.db.flush()
        return True

    async def request_self_recovery(self, email: str) -> Optional[EmailMessage]:
        """
        "¿Olvidaste tu contraseña?". No revela nada: correo desconocido, usuario
        inactivo, tope por hora o fallo del proveedor responden igual que el éxito.

        Devuelve el correo por enviar (o None) en vez de enviarlo: quien llama lo
        manda **después** de responder. Si se esperara al proveedor aquí, un
        correo registrado tardaría ~200 ms más y el tiempo delataría qué correos
        existen.
        """
        user = await UserRepository(self.db).get_by_email_global(email.strip())
        if user is None or not user.is_active or user.tenant is None:
            return None
        now = datetime.now(timezone.utc)
        recent = (await self.db.execute(
            select(func.count(LoginCode.id)).where(
                LoginCode.user_id == user.id,
                LoginCode.origin == LoginCodeOrigin.SELF,
                LoginCode.created_at > now - timedelta(hours=1),
            )
        )).scalar_one()
        if recent >= settings.LOGIN_CODE_MAX_REQUESTS_PER_HOUR:
            logger.info("Recuperación: tope por hora alcanzado para un usuario.")
            return None
        code, expires_at = await self.issue(user, LoginCodeOrigin.SELF, now=now)
        await self.db.commit()
        return login_code_email(user.email, user.full_name, code, expires_at, assisted=False)

