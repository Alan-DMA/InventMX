# Importación de módulos de tiempo y fecha
from datetime import date, datetime, timezone
# Importación de precisión decimal
from decimal import Decimal
# Importación de tipado
from typing import Any, Dict, List, Optional, Tuple
# Importación de identificadores UUID
import uuid

# Importación de SQLAlchemy
from sqlalchemy import extract, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan, TenantStatus
from app.modules.auth_tenancy.domain.user import User
from app.modules.inventory.domain.product import Product
from app.modules.saas_billing.domain.subscription_invoice import (
    SubscriptionInvoice,
    SubscriptionInvoiceStatus,
)
from app.modules.saas_billing.domain.webhook_log import WebhookLog
from app.modules.sales_pos.domain.sale import Sale, SaleStatus


class SubscriptionRepository:
    """
    Repositorio de persistencia asíncrona para facturación SaaS y suscripciones.
    Asegura integridad transaccional y consultas optimizadas para multi-inquilino.
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_tenant_by_id(self, tenant_id: uuid.UUID) -> Optional[Tenant]:
        """Obtiene la entidad Tenant por su identificador primario."""
        stmt = select(Tenant).where(Tenant.id == tenant_id)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def update_tenant_plan_and_status(
        self,
        tenant_id: uuid.UUID,
        plan: Optional[TenantPlan] = None,
        status: Optional[TenantStatus] = None,
    ) -> Optional[Tenant]:
        """Actualiza el plan o el estado operativo del inquilino."""
        tenant = await self.get_tenant_by_id(tenant_id)
        if not tenant:
            return None

        if plan is not None:
            tenant.plan_id = plan
        if status is not None:
            tenant.status = status

        tenant.updated_at = datetime.now(timezone.utc)
        await self.session.flush()
        return tenant

    async def create_invoice(self, invoice: SubscriptionInvoice) -> SubscriptionInvoice:
        """Registra y persiste una nueva factura de suscripción SaaS."""
        self.session.add(invoice)
        await self.session.flush()
        await self.session.refresh(invoice)
        return invoice

    async def get_invoice_by_id(
        self,
        invoice_id: uuid.UUID,
        tenant_id: Optional[uuid.UUID] = None,
    ) -> Optional[SubscriptionInvoice]:
        """Recupera una factura por su UUID, con validación opcional de pertenencia al tenant."""
        stmt = select(SubscriptionInvoice).where(SubscriptionInvoice.id == invoice_id)
        if tenant_id:
            stmt = stmt.where(SubscriptionInvoice.tenant_id == tenant_id)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_invoice_by_reference(self, reference_id: str) -> Optional[SubscriptionInvoice]:
        """Localiza una factura por su referencia bancaria SPEI o código de barras OXXO."""
        stmt = select(SubscriptionInvoice).where(
            (SubscriptionInvoice.payment_reference == reference_id)
            | (SubscriptionInvoice.oxxo_reference == reference_id)
            | (SubscriptionInvoice.clabe == reference_id)
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_invoices(
        self,
        tenant_id: uuid.UUID,
        status_filter: Optional[SubscriptionInvoiceStatus] = None,
        year: Optional[int] = None,
        month: Optional[int] = None,
        limit: int = 20,
        offset: int = 0,
    ) -> Tuple[List[SubscriptionInvoice], int]:
        """Retorna lista paginada de facturas del tenant junto con el total de registros."""
        query = select(SubscriptionInvoice).where(SubscriptionInvoice.tenant_id == tenant_id)

        if status_filter:
            query = query.where(SubscriptionInvoice.status == status_filter)
        if year:
            query = query.where(extract("year", SubscriptionInvoice.created_at) == year)
        if month:
            query = query.where(extract("month", SubscriptionInvoice.created_at) == month)

        # Conteo total
        count_stmt = select(func.count()).select_from(query.subquery())
        total_count = (await self.session.execute(count_stmt)).scalar() or 0

        # Paginación ordenada por fecha descendente
        stmt = query.order_by(SubscriptionInvoice.created_at.desc()).limit(limit).offset(offset)
        result = await self.session.execute(stmt)
        return list(result.scalars().all()), total_count

    async def get_invoices_summary(self, tenant_id: uuid.UUID) -> Dict[str, Any]:
        """Calcula el resumen financiero del historial de facturas del inquilino."""
        stmt_paid = select(func.coalesce(func.sum(SubscriptionInvoice.amount_mxn), Decimal("0.00"))).where(
            SubscriptionInvoice.tenant_id == tenant_id,
            SubscriptionInvoice.status == SubscriptionInvoiceStatus.PAID,
        )
        total_paid = (await self.session.execute(stmt_paid)).scalar() or Decimal("0.00")

        stmt_pending = select(func.coalesce(func.sum(SubscriptionInvoice.amount_mxn), Decimal("0.00"))).where(
            SubscriptionInvoice.tenant_id == tenant_id,
            SubscriptionInvoice.status.in_([SubscriptionInvoiceStatus.PENDING, SubscriptionInvoiceStatus.OVERDUE]),
        )
        pending_amount = (await self.session.execute(stmt_pending)).scalar() or Decimal("0.00")

        stmt_overdue = select(func.count(SubscriptionInvoice.id)).where(
            SubscriptionInvoice.tenant_id == tenant_id,
            SubscriptionInvoice.status == SubscriptionInvoiceStatus.OVERDUE,
        )
        overdue_count = (await self.session.execute(stmt_overdue)).scalar() or 0

        return {
            "total_paid_mxn": Decimal(str(total_paid)),
            "pending_amount_mxn": Decimal(str(pending_amount)),
            "overdue_count": overdue_count,
        }

    async def log_webhook_event(
        self,
        provider: str,
        reference_id: str,
        payload: Dict[str, Any],
        processed: bool = False,
    ) -> WebhookLog:
        """Registra la recepción de un webhook en la bitácora inmutable."""
        log = WebhookLog(
            provider=provider,
            reference_id=reference_id,
            payload=payload,
            processed=processed,
        )
        self.session.add(log)
        await self.session.flush()
        return log

    async def count_tenant_products(self, tenant_id: uuid.UUID) -> int:
        """Cuenta la cantidad de productos activos creados por el comercio."""
        stmt = select(func.count(Product.id)).where(
            Product.tenant_id == tenant_id,
            Product.is_active.is_(True),
        )
        return (await self.session.execute(stmt)).scalar() or 0

    async def count_tenant_users(self, tenant_id: uuid.UUID) -> int:
        """Cuenta los usuarios asignados al inquilino."""
        stmt = select(func.count(User.id)).where(
            User.tenant_id == tenant_id,
            User.is_active.is_(True),
        )
        return (await self.session.execute(stmt)).scalar() or 0

    async def get_tenant_monthly_sales(
        self,
        tenant_id: uuid.UUID,
        start_date: datetime,
        end_date: datetime,
    ) -> Decimal:
        """Calcula el total de ventas completadas en el periodo actual."""
        stmt = select(func.coalesce(func.sum(Sale.total_mxn), Decimal("0.00"))).where(
            Sale.tenant_id == tenant_id,
            Sale.status == SaleStatus.COMPLETED,
            Sale.created_at >= start_date,
            Sale.created_at <= end_date,
        )
        total = (await self.session.execute(stmt)).scalar() or Decimal("0.00")
        return Decimal(str(total))
