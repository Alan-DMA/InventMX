"""
Escritura y lectura de la bitácora de plataforma.

La cadena de hash: `row_hash = sha256(prev_hash + contenido canónico)`. Para que
dos escrituras simultáneas no bifurquen la cadena, cada anexo toma un candado
de transacción (`pg_advisory_xact_lock`) antes de leer el último hash.
"""
# Importación de módulos estándar
import hashlib
import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Sequence, Tuple

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.platform_admin.domain.audit_log import PlatformAuditLog

# Llave del candado consultivo de la bitácora (constante arbitraria del módulo)
_AUDIT_LOCK_KEY = 7_311_2026


@dataclass(frozen=True)
class RequestMeta:
    """De dónde vino la acción; va a la bitácora pero no al hash."""
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None


def _canonical(entry: PlatformAuditLog) -> str:
    """Contenido que firma el hash, en un orden y formato estables."""
    occurred = entry.occurred_at.astimezone(timezone.utc).isoformat()
    return json.dumps(
        {
            "occurred_at": occurred,
            "operator_id": str(entry.operator_id) if entry.operator_id else None,
            "action": entry.action,
            "target_tenant_id": str(entry.target_tenant_id) if entry.target_tenant_id else None,
            "target_type": entry.target_type,
            "target_id": entry.target_id,
            "reason": entry.reason,
            "details": entry.details or {},
            "prev_hash": entry.prev_hash,
        },
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
    )


def compute_hash(entry: PlatformAuditLog) -> str:
    return hashlib.sha256(_canonical(entry).encode("utf-8")).hexdigest()


def _plain(details: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Sólo tipos JSON simples (Decimal, UUID y fechas como texto): JSONB no reordena nada que afecte al hash."""
    return json.loads(json.dumps(details or {}, default=str))


class AuditRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def append(
        self,
        action: str,
        operator_id: Optional[uuid.UUID] = None,
        target_tenant_id: Optional[uuid.UUID] = None,
        target_type: Optional[str] = None,
        target_id: Optional[str] = None,
        reason: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
        meta: RequestMeta = RequestMeta(),
    ) -> PlatformAuditLog:
        """Anexa un renglón encadenado. Lo confirma la transacción de quien llama."""
        await self.db.execute(text("SELECT pg_advisory_xact_lock(:k)"), {"k": _AUDIT_LOCK_KEY})
        prev_hash = (await self.db.execute(
            select(PlatformAuditLog.row_hash).order_by(PlatformAuditLog.id.desc()).limit(1)
        )).scalar_one_or_none()

        entry = PlatformAuditLog(
            occurred_at=datetime.now(timezone.utc),
            operator_id=operator_id,
            action=action,
            target_tenant_id=target_tenant_id,
            target_type=target_type,
            target_id=target_id,
            reason=reason,
            details=_plain(details),
            ip_address=(meta.ip_address or None),
            user_agent=(meta.user_agent or "")[:255] or None,
            prev_hash=prev_hash,
        )
        entry.row_hash = compute_hash(entry)
        self.db.add(entry)
        await self.db.flush()
        return entry

    async def list(
        self,
        tenant_id: Optional[uuid.UUID] = None,
        operator_id: Optional[uuid.UUID] = None,
        actions: Optional[Sequence[str]] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[PlatformAuditLog], int]:
        conditions = []
        if tenant_id is not None:
            conditions.append(PlatformAuditLog.target_tenant_id == tenant_id)
        if operator_id is not None:
            conditions.append(PlatformAuditLog.operator_id == operator_id)
        if actions:
            conditions.append(PlatformAuditLog.action.in_(list(actions)))

        total = (await self.db.execute(
            select(func.count(PlatformAuditLog.id)).where(*conditions)
        )).scalar_one()
        rows = (await self.db.execute(
            select(PlatformAuditLog)
            .where(*conditions)
            .order_by(PlatformAuditLog.id.desc())
            .limit(limit)
            .offset(offset)
        )).scalars().all()
        return list(rows), int(total)

    async def verify_chain(self) -> Tuple[bool, int, Optional[int]]:
        """Recorre la bitácora completa. Devuelve (íntegra, revisados, primer id roto)."""
        rows = (await self.db.execute(
            select(PlatformAuditLog).order_by(PlatformAuditLog.id.asc())
        )).scalars().all()
        expected_prev: Optional[str] = None
        for checked, row in enumerate(rows, start=1):
            if row.prev_hash != expected_prev or compute_hash(row) != row.row_hash:
                return False, checked, row.id
            expected_prev = row.row_hash
        return True, len(rows), None
