import uuid
from typing import Optional, List
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan, TenantStatus


class TenantRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_id(self, tenant_id: uuid.UUID) -> Optional[Tenant]:
        stmt = select(Tenant).where(Tenant.id == tenant_id)
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_slug(self, slug: str) -> Optional[Tenant]:
        stmt = select(Tenant).where(Tenant.slug == slug)
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def create(
        self,
        name: str,
        slug: str,
        plan_id: TenantPlan = TenantPlan.EMPRENDEDOR,
        rfc: Optional[str] = None,
        legal_name: Optional[str] = None,
        enable_usd_secondary: bool = False,
    ) -> Tenant:
        tenant = Tenant(
            id=uuid.uuid4(),
            name=name,
            slug=slug,
            plan_id=plan_id,
            status=TenantStatus.ACTIVE,
            rfc=rfc,
            legal_name=legal_name,
            enable_usd_secondary=enable_usd_secondary,
        )
        self.db.add(tenant)
        await self.db.flush()
        return tenant
