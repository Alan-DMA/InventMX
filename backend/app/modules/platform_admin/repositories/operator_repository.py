"""Acceso a operadores de plataforma y sus códigos de recuperación."""
import hashlib
import secrets
import uuid
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.platform_admin.domain.operator import PlatformOperator, PlatformRecoveryCode

RECOVERY_CODES_COUNT = 10


def hash_recovery_code(code: str) -> str:
    """Normaliza (sin guiones ni espacios, mayúsculas) y hashea."""
    normalized = code.replace("-", "").replace(" ", "").strip().upper()
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def _new_recovery_code() -> str:
    raw = secrets.token_hex(5).upper()  # 10 caracteres
    return f"{raw[:5]}-{raw[5:]}"


class OperatorRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_email(self, email: str) -> Optional[PlatformOperator]:
        return (await self.db.execute(
            select(PlatformOperator).where(func.lower(PlatformOperator.email) == email.strip().lower())
        )).scalar_one_or_none()

    async def get_by_id(self, operator_id: uuid.UUID) -> Optional[PlatformOperator]:
        return (await self.db.execute(
            select(PlatformOperator).where(PlatformOperator.id == operator_id)
        )).scalar_one_or_none()

    async def names_by_id(self, ids: List[uuid.UUID]) -> dict:
        if not ids:
            return {}
        rows = (await self.db.execute(
            select(PlatformOperator.id, PlatformOperator.full_name).where(PlatformOperator.id.in_(ids))
        )).all()
        return {row[0]: row[1] for row in rows}

    async def replace_recovery_codes(self, operator_id: uuid.UUID) -> List[str]:
        """Invalida los anteriores y crea 10 nuevos. Los códigos en claro sólo salen aquí."""
        await self.db.execute(
            delete(PlatformRecoveryCode).where(PlatformRecoveryCode.operator_id == operator_id)
        )
        codes = [_new_recovery_code() for _ in range(RECOVERY_CODES_COUNT)]
        for code in codes:
            self.db.add(PlatformRecoveryCode(operator_id=operator_id, code_hash=hash_recovery_code(code)))
        await self.db.flush()
        return codes

    async def consume_recovery_code(self, operator_id: uuid.UUID, code: str) -> bool:
        row = (await self.db.execute(
            select(PlatformRecoveryCode).where(
                PlatformRecoveryCode.operator_id == operator_id,
                PlatformRecoveryCode.code_hash == hash_recovery_code(code),
                PlatformRecoveryCode.used_at.is_(None),
            )
        )).scalar_one_or_none()
        if row is None:
            return False
        row.used_at = datetime.now(timezone.utc)
        await self.db.flush()
        return True

    async def remaining_recovery_codes(self, operator_id: uuid.UUID) -> int:
        return int((await self.db.execute(
            select(func.count(PlatformRecoveryCode.id)).where(
                PlatformRecoveryCode.operator_id == operator_id,
                PlatformRecoveryCode.used_at.is_(None),
            )
        )).scalar_one())
