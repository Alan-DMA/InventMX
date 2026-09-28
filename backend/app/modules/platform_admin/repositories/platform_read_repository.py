"""
Único punto del panel que lee **entre comercios** (salta RLS).

Decisión P2 de Eduardo: el panel ve metadatos, no contenido. Por eso este
repositorio sólo toca una lista cerrada de tablas —`tenants`, `users` (contacto,
conteo, rol y último acceso), `roles` (para saber quién es el dueño),
`warehouses` y `catalog_settings` (sólo nombre/estado, para el diagnóstico),
`login_codes` (si hay un código asistido sin usar; nunca el código) y
`support_access_grants`— y el módulo no importa dominios de contenido (lo vigila
el test de arquitectura en `tests/unit/test_platform_admin.py`). Almacenes y
vitrina se leen con SQL de columnas contadas por esa misma razón.

El salto de RLS es local a la transacción (`set_config(..., true)`) y se apaga
al terminar cada consulta.
"""
import uuid
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Dict, List, Optional, Sequence, Tuple

from sqlalchemy import func, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.modules.auth_tenancy.domain.login_code import LoginCode, LoginCodeOrigin
from app.modules.auth_tenancy.domain.role import Role
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan, TenantStatus
from app.modules.auth_tenancy.domain.user import User
from app.modules.platform_admin.domain.support import SupportAccessGrant

# Tablas que el panel puede leer entre comercios (documental; lo vigila el test)
ALLOWED_TABLES = (
    "tenants", "users", "roles", "warehouses", "catalog_settings", "login_codes", "support_access_grants",
)


class PlatformReadRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    @asynccontextmanager
    async def _cross_tenant(self):
        await self.db.execute(text("SELECT set_config('app.bypass_rls', 'on', true);"))
        try:
            yield
        finally:
            await self.db.execute(text("SELECT set_config('app.bypass_rls', 'off', true);"))

    @asynccontextmanager
    async def _as_tenant(self, tenant_id: uuid.UUID):
        """
        Para tablas cuya política no acepta el salto (p. ej. `warehouses`): se
        lee *como* ese comercio, sólo en esta transacción y sólo las columnas
        contadas de la consulta.
        """
        await self.db.execute(
            text("SELECT set_config('app.current_tenant', :t, true);"), {"t": str(tenant_id)}
        )
        try:
            yield
        finally:
            await self.db.execute(text("SELECT set_config('app.current_tenant', '', true);"))

    # ── Subconsultas de metadatos por comercio ─────────────────────────────

    @staticmethod
    def _owner_subquery(column):
        """Nombre o correo del Dueño más antiguo del comercio."""
        return (
            select(column)
            .join(Role, Role.id == User.role_id)
            .where(User.tenant_id == Tenant.id, Role.name == "OWNER")
            .order_by(User.created_at.asc())
            .limit(1)
            .scalar_subquery()
        )

    def _summary_columns(self):
        users_count = (
            select(func.count(User.id))
            .where(User.tenant_id == Tenant.id, User.is_active.is_(True))
            .scalar_subquery()
        )
        last_login = (
            select(func.max(User.last_login_at)).where(User.tenant_id == Tenant.id).scalar_subquery()
        )
        return (
            Tenant,
            self._owner_subquery(User.full_name).label("owner_name"),
            self._owner_subquery(User.email).label("owner_email"),
            users_count.label("users_count"),
            last_login.label("last_activity_at"),
        )

    # ── Comercios ──────────────────────────────────────────────────────────

    async def list_tenants(
        self,
        status: Optional[TenantStatus] = None,
        plan: Optional[TenantPlan] = None,
        query: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[tuple], int]:
        conditions = []
        if status is not None:
            conditions.append(Tenant.status == status)
        if plan is not None:
            conditions.append(Tenant.plan_id == plan)
        if query:
            like = f"%{query.strip()}%"
            owner_match = (
                select(User.id)
                .where(User.tenant_id == Tenant.id, User.email.ilike(like))
                .exists()
            )
            conditions.append(or_(Tenant.name.ilike(like), Tenant.slug.ilike(like), owner_match))

        async with self._cross_tenant():
            total = (await self.db.execute(
                select(func.count(Tenant.id)).where(*conditions)
            )).scalar_one()
            rows = (await self.db.execute(
                select(*self._summary_columns())
                .where(*conditions)
                .order_by(Tenant.created_at.desc())
                .limit(limit)
                .offset(offset)
            )).all()
        return list(rows), int(total)

    async def get_tenant_summary(self, tenant_id: uuid.UUID) -> Optional[tuple]:
        async with self._cross_tenant():
            return (await self.db.execute(
                select(*self._summary_columns()).where(Tenant.id == tenant_id)
            )).first()

    async def get_tenant(self, tenant_id: uuid.UUID) -> Optional[Tenant]:
        return (await self.db.execute(select(Tenant).where(Tenant.id == tenant_id))).scalar_one_or_none()

    async def tenant_names(self, ids: Sequence[uuid.UUID]) -> Dict[uuid.UUID, str]:
        if not ids:
            return {}
        rows = (await self.db.execute(select(Tenant.id, Tenant.name).where(Tenant.id.in_(list(ids))))).all()
        return {row[0]: row[1] for row in rows}

    async def get_owner(self, tenant_id: uuid.UUID) -> Optional[User]:
        """El Dueño más antiguo: a él le llegan los códigos, la exportación y los avisos."""
        async with self._cross_tenant():
            return (await self.db.execute(
                select(User)
                .join(Role, Role.id == User.role_id)
                .where(User.tenant_id == tenant_id, Role.name == "OWNER", User.is_active.is_(True))
                .options(selectinload(User.tenant), selectinload(User.role))
                .order_by(User.created_at.asc())
                .limit(1)
            )).scalar_one_or_none()

    async def count_active_users(self, tenant_id: uuid.UUID) -> int:
        async with self._cross_tenant():
            return int((await self.db.execute(
                select(func.count(User.id)).where(User.tenant_id == tenant_id, User.is_active.is_(True))
            )).scalar_one())

    # ── Diagnóstico (sólo metadatos) ───────────────────────────────────────

    async def diagnostic_users(self, tenant_id: uuid.UUID) -> List[tuple]:
        async with self._cross_tenant():
            return list((await self.db.execute(
                select(User.full_name, User.email, Role.name, User.is_active, User.last_login_at)
                .outerjoin(Role, Role.id == User.role_id)
                .where(User.tenant_id == tenant_id)
                .order_by(User.is_active.desc(), User.created_at.asc())
            )).all())

    async def diagnostic_warehouses(self, tenant_id: uuid.UUID) -> List[tuple]:
        async with self._as_tenant(tenant_id):
            return list((await self.db.execute(
                text(
                    "SELECT name, is_active, is_default FROM warehouses "
                    "WHERE tenant_id = :t ORDER BY is_default DESC, name"
                ),
                {"t": tenant_id},
            )).all())

    async def catalog_enabled(self, tenant_id: uuid.UUID) -> Optional[bool]:
        async with self._cross_tenant():
            return (await self.db.execute(
                text("SELECT is_catalog_enabled FROM catalog_settings WHERE tenant_id = :t LIMIT 1"),
                {"t": tenant_id},
            )).scalar_one_or_none()

    # ── Lo que está en curso (feed y ficha) ────────────────────────────────

    async def active_grants(self, now: datetime, tenant_id: Optional[uuid.UUID] = None) -> List[SupportAccessGrant]:
        conditions = [SupportAccessGrant.revoked_at.is_(None), SupportAccessGrant.expires_at > now]
        if tenant_id is not None:
            conditions.append(SupportAccessGrant.tenant_id == tenant_id)
        async with self._cross_tenant():
            return list((await self.db.execute(
                select(SupportAccessGrant).where(*conditions).order_by(SupportAccessGrant.expires_at.desc())
            )).scalars().all())

    async def unused_assisted_codes(self, now: datetime, tenant_id: Optional[uuid.UUID] = None) -> List[LoginCode]:
        """Códigos asistidos enviados y sin usar (sólo fechas: el hash no sale de aquí)."""
        conditions = [
            LoginCode.origin == LoginCodeOrigin.ASSISTED,
            LoginCode.used_at.is_(None),
            LoginCode.invalidated_at.is_(None),
            LoginCode.expires_at > now,
        ]
        if tenant_id is not None:
            conditions.append(LoginCode.tenant_id == tenant_id)
        return list((await self.db.execute(
            select(LoginCode).where(*conditions).order_by(LoginCode.created_at.desc())
        )).scalars().all())

    async def abuse_suspended_tenants(self) -> List[Tenant]:
        return list((await self.db.execute(
            select(Tenant).where(Tenant.status == TenantStatus.HARD_LOCK, Tenant.lock_reason == "ABUSE")
        )).scalars().all())

    # ── Métricas y feed ────────────────────────────────────────────────────

    async def tenants_by_status_and_plan(self) -> List[tuple]:
        return list((await self.db.execute(
            select(Tenant.status, Tenant.plan_id, func.count(Tenant.id)).group_by(Tenant.status, Tenant.plan_id)
        )).all())

    async def signups_since(self, since: datetime) -> int:
        return int((await self.db.execute(
            select(func.count(Tenant.id)).where(Tenant.created_at >= since)
        )).scalar_one())

    async def signups_between(self, since: datetime, until: datetime) -> List[Tenant]:
        return list((await self.db.execute(
            select(Tenant)
            .where(Tenant.created_at >= since, Tenant.created_at < until)
            .order_by(Tenant.created_at.desc())
        )).scalars().all())
