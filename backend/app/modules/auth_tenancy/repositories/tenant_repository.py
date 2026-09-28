from decimal import Decimal
import uuid
from datetime import datetime, timezone
from typing import Optional, List
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan, TenantStatus
from app.modules.saas_billing.services.entitlement import SubscriptionSource, add_one_month


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
        now = datetime.now(timezone.utc)
        tenant = Tenant(
            id=uuid.uuid4(),
            name=name,
            slug=slug,
            plan_id=plan_id,
            status=TenantStatus.ACTIVE,
            rfc=rfc,
            legal_name=legal_name,
            enable_usd_secondary=enable_usd_secondary,
            # Primer mes desde el registro (modelo prepago, P9–P13)
            paid_until=add_one_month(now),
            subscription_source=SubscriptionSource.TRIAL.value,
        )
        self.db.add(tenant)
        await self.db.flush()
        return tenant

    async def update_max_margin_percent(
        self, tenant: Tenant, max_margin_percent: Decimal
    ) -> Tenant:
        tenant.max_margin_percent = max_margin_percent
        self.db.add(tenant)
        await self.db.flush()
        return tenant
