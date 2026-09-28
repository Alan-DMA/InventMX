"""
Único punto del panel que lee **entre comercios** (salta RLS).

Decisión P2 de Eduardo: el panel ve metadatos, no contenido. Por eso este
repositorio sólo toca una lista cerrada de tablas —`tenants`, `users` (contacto,
conteo y último acceso), `roles` (para saber quién es el dueño) y
`subscription_invoices`— y el módulo no importa dominios de contenido (lo vigila
`tests/unit/test_platform_architecture.py`).

El salto de RLS es local a la transacción (`set_config(..., true)`) y se apaga
al terminar cada consulta.
"""
import uuid
from contextlib import asynccontextmanager
from datetime import datetime
from decimal import Decimal
from typing import List, Optional, Sequence, Tuple

from sqlalchemy import func, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.auth_tenancy.domain.role import Role
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan, TenantStatus
from app.modules.auth_tenancy.domain.user import User
from app.modules.saas_billing.domain.subscription_invoice import (
    SubscriptionInvoice,
    SubscriptionInvoiceStatus,
)

# Tablas que el panel puede leer entre comercios (documental; lo vigila el test)
ALLOWED_TABLES = ("tenants", "users", "roles", "subscription_invoices")

OPEN_INVOICE_STATUSES = (SubscriptionInvoiceStatus.PENDING, SubscriptionInvoiceStatus.OVERDUE)


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
        open_invoices = (
            select(func.count(SubscriptionInvoice.id))
            .where(
                SubscriptionInvoice.tenant_id == Tenant.id,
                SubscriptionInvoice.status.in_(OPEN_INVOICE_STATUSES),
            )
            .scalar_subquery()
        )
        return (
            Tenant,
            self._owner_subquery(User.full_name).label("owner_name"),
            self._owner_subquery(User.email).label("owner_email"),
            users_count.label("users_count"),
            last_login.label("last_activity_at"),
            open_invoices.label("open_invoices"),
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

    async def count_active_users(self, tenant_id: uuid.UUID) -> int:
        async with self._cross_tenant():
            return int((await self.db.execute(
                select(func.count(User.id)).where(User.tenant_id == tenant_id, User.is_active.is_(True))
            )).scalar_one())

    # ── Facturas ───────────────────────────────────────────────────────────

    async def list_invoices(
        self,
        tenant_id: Optional[uuid.UUID] = None,
        statuses: Optional[Sequence[SubscriptionInvoiceStatus]] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[tuple], int]:
        conditions = []
        if tenant_id is not None:
            conditions.append(SubscriptionInvoice.tenant_id == tenant_id)
        if statuses:
            conditions.append(SubscriptionInvoice.status.in_(list(statuses)))
        # La bandeja (sin comercio) va por lo más atrasado primero; el detalle, por lo más reciente
        order = (
            SubscriptionInvoice.period_end.desc()
            if tenant_id is not None
            else SubscriptionInvoice.period_end.asc()
        )
        async with self._cross_tenant():
            total = (await self.db.execute(
                select(func.count(SubscriptionInvoice.id)).where(*conditions)
            )).scalar_one()
            rows = (await self.db.execute(
                select(SubscriptionInvoice, Tenant.name)
                .join(Tenant, Tenant.id == SubscriptionInvoice.tenant_id)
                .where(*conditions)
                .order_by(order, SubscriptionInvoice.created_at.desc())
                .limit(limit)
                .offset(offset)
            )).all()
        return list(rows), int(total)

    async def get_invoice(self, invoice_id: uuid.UUID) -> Optional[SubscriptionInvoice]:
        async with self._cross_tenant():
            return (await self.db.execute(
                select(SubscriptionInvoice).where(SubscriptionInvoice.id == invoice_id)
            )).scalar_one_or_none()

    async def count_overdue_invoices(self, tenant_id: uuid.UUID, exclude_id: Optional[uuid.UUID] = None) -> int:
        conditions = [
            SubscriptionInvoice.tenant_id == tenant_id,
            SubscriptionInvoice.status == SubscriptionInvoiceStatus.OVERDUE,
        ]
        if exclude_id is not None:
            conditions.append(SubscriptionInvoice.id != exclude_id)
        async with self._cross_tenant():
            return int((await self.db.execute(
                select(func.count(SubscriptionInvoice.id)).where(*conditions)
            )).scalar_one())

    async def latest_period_end(self, tenant_id: uuid.UUID):
        async with self._cross_tenant():
            return (await self.db.execute(
                select(func.max(SubscriptionInvoice.period_end)).where(
                    SubscriptionInvoice.tenant_id == tenant_id,
                    SubscriptionInvoice.status == SubscriptionInvoiceStatus.PAID,
                )
            )).scalar_one_or_none()

    # ── Métricas (Constitución §5.3) ───────────────────────────────────────

    async def tenants_by_status_and_plan(self) -> List[tuple]:
        return list((await self.db.execute(
            select(Tenant.status, Tenant.plan_id, func.count(Tenant.id)).group_by(Tenant.status, Tenant.plan_id)
        )).all())

    async def signups_since(self, since: datetime) -> int:
        return int((await self.db.execute(
            select(func.count(Tenant.id)).where(Tenant.created_at >= since)
        )).scalar_one())

    async def open_invoices_totals(self) -> Tuple[int, Decimal]:
        async with self._cross_tenant():
            row = (await self.db.execute(
                select(func.count(SubscriptionInvoice.id), func.coalesce(func.sum(SubscriptionInvoice.amount_mxn), 0))
                .where(SubscriptionInvoice.status.in_(OPEN_INVOICE_STATUSES))
            )).one()
        return int(row[0]), Decimal(row[1])
