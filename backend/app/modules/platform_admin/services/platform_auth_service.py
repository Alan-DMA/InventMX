"""
Acceso al panel: contraseña → reto de 5 min → código de Google Authenticator (P3).

- Primer acceso: el reto es de vinculación; se muestra el QR y el primer código
  válido activa TOTP y entrega 10 códigos de recuperación (una sola vez).
- 5 fallos (contraseña o código) bloquean la cuenta 15 minutos.
- Un correo desconocido cuesta lo mismo que uno válido (se verifica contra un
  hash de relleno): el tiempo de respuesta no delata qué correos existen.
- Todo queda en la bitácora, incluidos los fallos.
"""
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config.settings import settings
from app.core.security.password import get_password_hash, verify_password
from app.modules.platform_admin.domain.audit_log import AuditAction
from app.modules.platform_admin.domain.operator import PlatformOperator
from app.modules.platform_admin.repositories.audit_repository import AuditRepository, RequestMeta
from app.modules.platform_admin.repositories.operator_repository import OperatorRepository
from app.modules.platform_admin.schemas.platform_schemas import (
    LoginResponse,
    OperatorRead,
    SessionResponse,
)
from app.modules.platform_admin.security import secret_box, tokens, totp

# Hash bcrypt de una contraseña que nadie tiene: iguala el tiempo con correos
# inexistentes. Se genera una vez (tiene que ser un bcrypt válido para costar lo mismo).
_dummy_hash: Optional[str] = None


def _dummy_password_hash() -> str:
    global _dummy_hash
    if _dummy_hash is None:
        _dummy_hash = get_password_hash(secrets.token_hex(16))
    return _dummy_hash

_INVALID = "Correo, contraseña o código incorrectos."


def _unauthorized(message: str = _INVALID) -> HTTPException:
    return HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=message)


class PlatformAuthService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.operators = OperatorRepository(db)
        self.audit = AuditRepository(db)

    # ── Paso 1: contraseña ────────────────────────────────────────────────

    async def login(self, email: str, password: str, meta: RequestMeta) -> LoginResponse:
        operator = await self.operators.get_by_email(email)
        if operator is None or not operator.is_active:
            verify_password(password, _dummy_password_hash())
            await self.audit.append(
                AuditAction.LOGIN_FAILED,
                details={"email": email.strip().lower(), "motivo": "correo desconocido o inactivo"},
                meta=meta,
            )
            await self.db.commit()
            raise _unauthorized()

        self._ensure_not_locked(operator)

        if not verify_password(password, operator.hashed_password):
            await self._register_failure(operator, AuditAction.LOGIN_FAILED, "contraseña incorrecta", meta)
            raise _unauthorized()

        if operator.totp_enabled:
            await self.db.commit()
            return LoginResponse(
                status="TOTP_REQUIRED",
                challenge_token=tokens.create_challenge_token(operator.id, tokens.PURPOSE_VERIFY),
            )

        # Primer acceso: vincular Google Authenticator. Se conserva el secreto
        # pendiente para que un QR ya escaneado siga sirviendo si reintenta.
        if operator.totp_secret_encrypted:
            secret = secret_box.decrypt(operator.totp_secret_encrypted)
        else:
            secret = totp.generate_secret()
            operator.totp_secret_encrypted = secret_box.encrypt(secret)
        await self.db.commit()
        return LoginResponse(
            status="ENROLLMENT_REQUIRED",
            challenge_token=tokens.create_challenge_token(operator.id, tokens.PURPOSE_ENROLL),
            otpauth_uri=totp.provisioning_uri(secret, operator.email),
            manual_secret=secret,
        )

    # ── Paso 2: código TOTP (vinculación o verificación) ──────────────────

    async def verify_totp(self, challenge_token: str, code: str, meta: RequestMeta) -> SessionResponse:
        operator, purpose = await self._operator_from_challenge(challenge_token)
        self._ensure_not_locked(operator)
        if not operator.totp_secret_encrypted:
            raise _unauthorized()

        secret = secret_box.decrypt(operator.totp_secret_encrypted)
        step = totp.verify(secret, code, operator.totp_last_step)
        if step is None:
            await self._register_failure(operator, AuditAction.TOTP_FAILED, "código incorrecto o repetido", meta)
            raise _unauthorized()

        operator.totp_last_step = step
        recovery_codes: Optional[list] = None
        if purpose == tokens.PURPOSE_ENROLL and not operator.totp_enabled:
            operator.totp_enabled_at = datetime.now(timezone.utc)
            recovery_codes = await self.operators.replace_recovery_codes(operator.id)
            await self.audit.append(AuditAction.TOTP_ENROLLED, operator_id=operator.id, meta=meta)
        elif purpose == tokens.PURPOSE_ENROLL:
            # Reto de vinculación viejo, pero ya está vinculado: vale como verificación
            pass

        return await self._open_session(operator, meta, recovery_codes)

    # ── Alternativa: código de recuperación ───────────────────────────────

    async def login_with_recovery_code(
        self, challenge_token: str, recovery_code: str, meta: RequestMeta
    ) -> SessionResponse:
        operator, purpose = await self._operator_from_challenge(challenge_token)
        self._ensure_not_locked(operator)
        if purpose != tokens.PURPOSE_VERIFY or not operator.totp_enabled:
            raise _unauthorized()

        if not await self.operators.consume_recovery_code(operator.id, recovery_code):
            await self._register_failure(operator, AuditAction.TOTP_FAILED, "código de recuperación inválido", meta)
            raise _unauthorized()

        remaining = await self.operators.remaining_recovery_codes(operator.id)
        await self.audit.append(
            AuditAction.RECOVERY_CODE_USED,
            operator_id=operator.id,
            details={"restantes": remaining},
            meta=meta,
        )
        return await self._open_session(operator, meta)

    # ── Apoyo ──────────────────────────────────────────────────────────────

    async def _operator_from_challenge(self, challenge_token: str):
        payload = tokens.decode(challenge_token, tokens.CHALLENGE)
        operator = await self.operators.get_by_id(uuid.UUID(payload["sub"]))
        if operator is None or not operator.is_active:
            raise _unauthorized()
        return operator, payload.get("purpose")

    def _ensure_not_locked(self, operator: PlatformOperator) -> None:
        if operator.locked_until and operator.locked_until > datetime.now(timezone.utc):
            local = operator.locked_until.astimezone(timezone.utc).strftime("%H:%M UTC")
            raise HTTPException(
                status_code=status.HTTP_423_LOCKED,
                detail=f"Cuenta bloqueada por intentos fallidos hasta las {local}.",
            )

    async def _register_failure(
        self, operator: PlatformOperator, action: str, reason: str, meta: RequestMeta
    ) -> None:
        operator.failed_attempts = (operator.failed_attempts or 0) + 1
        await self.audit.append(
            action,
            operator_id=operator.id,
            details={"motivo": reason, "intentos": operator.failed_attempts},
            meta=meta,
        )
        if operator.failed_attempts >= settings.PLATFORM_MAX_FAILED_ATTEMPTS:
            operator.locked_until = datetime.now(timezone.utc) + timedelta(
                minutes=settings.PLATFORM_LOCKOUT_MINUTES
            )
            operator.failed_attempts = 0
            await self.audit.append(
                AuditAction.OPERATOR_LOCKED,
                operator_id=operator.id,
                details={"minutos": settings.PLATFORM_LOCKOUT_MINUTES},
                meta=meta,
            )
        await self.db.commit()

    async def _open_session(
        self,
        operator: PlatformOperator,
        meta: RequestMeta,
        recovery_codes: Optional[list] = None,
    ) -> SessionResponse:
        operator.failed_attempts = 0
        operator.locked_until = None
        operator.last_login_at = datetime.now(timezone.utc)
        await self.audit.append(AuditAction.LOGIN_SUCCEEDED, operator_id=operator.id, meta=meta)
        remaining = await self.operators.remaining_recovery_codes(operator.id)
        response = SessionResponse(
            access_token=tokens.create_access_token(operator.id),
            expires_in=settings.PLATFORM_TOKEN_EXPIRE_MINUTES * 60,
            operator=OperatorRead.model_validate(operator),
            recovery_codes=recovery_codes,
            recovery_codes_remaining=remaining,
        )
        await self.db.commit()
        return response
