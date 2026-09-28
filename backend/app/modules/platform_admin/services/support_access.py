"""
Acceso de soporte concedido por el dueño (P2/P18), del lado de su app.

Sin concesión vigente, soporte no puede asomarse al contenido de la tienda. El
dueño elige por cuánto tiempo (1 h, 24 h o 3 días), puede retirarla cuando
quiera y ve el historial. La suplantación de sólo lectura que usa la concesión
es la etapa 4; aquí sólo vive el permiso. Cada concesión y retiro va a la
bitácora de plataforma (el feed lo muestra); los hace el dueño, no un operador.
"""
from datetime import datetime, timedelta, timezone
from typing import List, Literal, Optional

from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import set_tenant_context
from app.modules.auth_tenancy.domain.user import User
from app.modules.platform_admin.domain.audit_log import AuditAction
from app.modules.platform_admin.domain.support import SupportAccessGrant
from app.modules.platform_admin.repositories.audit_repository import AuditRepository, RequestMeta

GrantHours = Literal[1, 24, 72]


class GrantRequest(BaseModel):
    hours: GrantHours = Field(..., description="Cuánto dura el permiso: 1, 24 o 72 horas")


class GrantRead(BaseModel):
    id: str
    created_at: datetime
    expires_at: datetime
    revoked_at: Optional[datetime] = None
    active: bool


class SupportAccessStatus(BaseModel):
    active: Optional[GrantRead] = None
    history: List[GrantRead]


def _read(grant: SupportAccessGrant, now: datetime) -> GrantRead:
    return GrantRead(
        id=str(grant.id),
        created_at=grant.created_at,
        expires_at=grant.expires_at,
        revoked_at=grant.revoked_at,
        active=grant.is_active(now),
    )


class SupportAccessService:
    """Corre con el contexto RLS del dueño en sesión (lo fija `get_current_user`)."""

    def __init__(self, db: AsyncSession, owner: User, meta: RequestMeta = RequestMeta()):
        self.db = db
        self.owner = owner
        self.meta = meta

    async def status(self) -> SupportAccessStatus:
        now = datetime.now(timezone.utc)
        grants = (await self.db.execute(
            select(SupportAccessGrant)
            .where(SupportAccessGrant.tenant_id == self.owner.tenant_id)
            .order_by(SupportAccessGrant.created_at.desc())
            .limit(10)
        )).scalars().all()
        active = next((g for g in grants if g.is_active(now)), None)
        return SupportAccessStatus(
            active=_read(active, now) if active else None,
            history=[_read(g, now) for g in grants],
        )

    async def grant(self, hours: int) -> SupportAccessStatus:
        """Una concesión nueva reemplaza a la vigente (no se acumulan)."""
        now = datetime.now(timezone.utc)
        await self._revoke_active(now)
        grant = SupportAccessGrant(
            tenant_id=self.owner.tenant_id,
            granted_by_user_id=self.owner.id,
            expires_at=now + timedelta(hours=hours),
        )
        self.db.add(grant)
        await self.db.flush()
        await AuditRepository(self.db).append(
            AuditAction.SUPPORT_ACCESS_GRANTED,
            target_tenant_id=self.owner.tenant_id,
            target_type="grant",
            target_id=str(grant.id),
            details={"horas": hours, "vence": grant.expires_at.isoformat()},
            meta=self.meta,
        )
        await self._commit()
        return await self.status()

    async def revoke(self) -> SupportAccessStatus:
        now = datetime.now(timezone.utc)
        revoked = await self._revoke_active(now)
        if revoked:
            await AuditRepository(self.db).append(
                AuditAction.SUPPORT_ACCESS_REVOKED,
                target_tenant_id=self.owner.tenant_id,
                target_type="grant",
                target_id=str(revoked[0].id),
                meta=self.meta,
            )
        await self._commit()
        return await self.status()

    async def _commit(self) -> None:
        # Tras el commit la sesión suelta la conexión y la siguiente puede ser
        # otra, sin el contexto RLS: se vuelve a fijar antes de leer.
        await self.db.commit()
        await set_tenant_context(self.db, self.owner.tenant_id)

    async def _revoke_active(self, now: datetime) -> List[SupportAccessGrant]:
        active = (await self.db.execute(
            select(SupportAccessGrant).where(
                SupportAccessGrant.tenant_id == self.owner.tenant_id,
                SupportAccessGrant.revoked_at.is_(None),
                SupportAccessGrant.expires_at > now,
            )
        )).scalars().all()
        for grant in active:
            grant.revoked_at = now
        await self.db.flush()
        return list(active)
