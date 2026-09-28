"""
Comercios, suscripciones, métricas y bitácora del panel (Fase 1).

Reglas que atraviesan todo:
- Sólo metadatos (P2): nada de ventas, productos, clientes ni cajas.
- Toda acción que cambia algo exige motivo y se anexa a la bitácora **en la
  misma transacción** que el cambio: o quedan los dos, o ninguno.
- Los bloqueos son manuales (P7): no hay proceso que pase a SOFT/HARD_LOCK solo.
- El Dueño ve lo que se hizo en su suscripción, con el motivo (P8).
"""
import calendar
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from typing import Dict, List, Optional

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import set_tenant_context
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan, TenantStatus
from app.modules.auth_tenancy.services.user_service import PLAN_USER_LIMITS
from app.modules.platform_admin.domain.audit_log import AuditAction, PlatformAuditLog
from app.modules.platform_admin.domain.operator import PlatformOperator
from app.modules.platform_admin.repositories.audit_repository import AuditRepository, RequestMeta
from app.modules.platform_admin.repositories.operator_repository import OperatorRepository
from app.modules.platform_admin.repositories.platform_read_repository import (
    OPEN_INVOICE_STATUSES,
    PlatformReadRepository,
)
from app.modules.platform_admin.schemas.platform_schemas import (
    AuditEntryRead,
    AuditPage,
    ChainVerification,
    ChangePlanRequest,
    ChangeStatusRequest,
    ConfirmPaymentRequest,
    CourtesyRequest,
    InvoicePage,
    InvoiceRead,
    PlatformMetrics,
    TenantDetail,
    TenantPage,
    TenantSummary,
)
from app.modules.saas_billing.domain.subscription_invoice import (
    SaasPaymentMethod,
    SubscriptionInvoice,
    SubscriptionInvoiceStatus,
)
from app.modules.saas_billing.domain.subscription_plan import AVAILABLE_PLANS


def _unprocessable(detail: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=detail)


def _not_found(detail: str = "Comercio no encontrado.") -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=detail)


def _add_one_month(start: date) -> date:
    """Mismo día del mes siguiente, o el último si no existe (31 ene → 28/29 feb)."""
    year = start.year + (start.month // 12)
    month = start.month % 12 + 1
    day = min(start.day, calendar.monthrange(year, month)[1])
    return date(year, month, day)


def _invoice_read(invoice: SubscriptionInvoice, tenant_name: Optional[str] = None) -> InvoiceRead:
    return InvoiceRead(
        id=invoice.id,
        tenant_id=invoice.tenant_id,
        tenant_name=tenant_name,
        plan=invoice.plan,
        amount_mxn=invoice.amount_mxn,
        payment_method=invoice.payment_method,
        status=invoice.status,
        period_start=invoice.period_start,
        period_end=invoice.period_end,
        payment_reference=invoice.payment_reference,
        paid_at=invoice.paid_at,
        created_at=invoice.created_at,
    )


def _summary(row) -> TenantSummary:
    tenant: Tenant = row[0]
    return TenantSummary(
        id=tenant.id,
        name=tenant.name,
        slug=tenant.slug,
        plan=tenant.plan_id,
        status=tenant.status,
        created_at=tenant.created_at,
        owner_name=row.owner_name,
        owner_email=row.owner_email,
        users_count=int(row.users_count or 0),
        users_limit=PLAN_USER_LIMITS.get(tenant.plan_id, 2),
        last_activity_at=row.last_activity_at,
        open_invoices=int(row.open_invoices or 0),
    )


class PlatformAdminService:
    def __init__(self, db: AsyncSession, operator: PlatformOperator, meta: RequestMeta = RequestMeta()):
        self.db = db
        self.operator = operator
        self.meta = meta
        self.reader = PlatformReadRepository(db)
        self.audit = AuditRepository(db)
        self.operators = OperatorRepository(db)

    # ── Comercios ──────────────────────────────────────────────────────────

    async def list_tenants(
        self,
        status_filter: Optional[TenantStatus],
        plan: Optional[TenantPlan],
        query: Optional[str],
        limit: int,
        offset: int,
    ) -> TenantPage:
        rows, total = await self.reader.list_tenants(status_filter, plan, query, limit, offset)
        return TenantPage(items=[_summary(r) for r in rows], total=total)

    async def get_tenant_detail(self, tenant_id: uuid.UUID) -> TenantDetail:
        """Abrir la ficha de un comercio queda registrado (sin motivo: es sólo lectura)."""
        if await self.reader.get_tenant(tenant_id) is None:
            raise _not_found()
        await self.audit.append(
            AuditAction.TENANT_VIEWED,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="tenant",
            target_id=str(tenant_id),
            meta=self.meta,
        )
        await self.db.commit()
        return await self._detail(tenant_id)

    async def _detail(self, tenant_id: uuid.UUID) -> TenantDetail:
        row = await self.reader.get_tenant_summary(tenant_id)
        if row is None:
            raise _not_found()
        invoices, _ = await self.reader.list_invoices(tenant_id=tenant_id, limit=24)
        activity, _ = await self.audit.list(tenant_id=tenant_id, limit=30)
        summary = _summary(row)
        return TenantDetail(
            **summary.model_dump(),
            invoices=[_invoice_read(inv, name) for inv, name in invoices],
            activity=await self._audit_reads(activity),
        )

    # ── Facturas ───────────────────────────────────────────────────────────

    async def list_open_invoices(self, limit: int, offset: int) -> InvoicePage:
        """Bandeja de pagos por conciliar (Constitución §5.3): lo más atrasado primero."""
        rows, total = await self.reader.list_invoices(statuses=OPEN_INVOICE_STATUSES, limit=limit, offset=offset)
        return InvoicePage(items=[_invoice_read(inv, name) for inv, name in rows], total=total)

    # ── Acciones de suscripción ────────────────────────────────────────────

    async def confirm_payment(self, tenant_id: uuid.UUID, data: ConfirmPaymentRequest) -> TenantDetail:
        tenant = await self._tenant_or_404(tenant_id)
        invoice = await self.reader.get_invoice(data.invoice_id)
        if invoice is None or invoice.tenant_id != tenant_id:
            raise _not_found("Factura no encontrada en este comercio.")
        if invoice.status not in OPEN_INVOICE_STATUSES:
            raise _unprocessable("Esta factura no está pendiente: no hay pago que confirmar.")

        await set_tenant_context(self.db, tenant_id)
        invoice.status = SubscriptionInvoiceStatus.PAID
        invoice.paid_at = datetime.now(timezone.utc)
        invoice.payment_method = SaasPaymentMethod(data.method)
        if data.reference:
            invoice.payment_reference = data.reference.strip()

        # Se reactiva sólo si ya no le queda nada vencido
        reactivated = False
        if tenant.status != TenantStatus.ACTIVE:
            if await self.reader.count_overdue_invoices(tenant_id, exclude_id=invoice.id) == 0:
                tenant.status = TenantStatus.ACTIVE
                reactivated = True

        await self.audit.append(
            AuditAction.PAYMENT_CONFIRMED,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="invoice",
            target_id=str(invoice.id),
            reason=data.reason,
            details={
                "monto_mxn": str(invoice.amount_mxn),
                "metodo": data.method.value if hasattr(data.method, "value") else str(data.method),
                "referencia": data.reference,
                "periodo": f"{invoice.period_start} a {invoice.period_end}",
                "reactivado": reactivated,
            },
            meta=self.meta,
        )
        await self.db.commit()
        return await self._detail(tenant_id)

    async def change_status(self, tenant_id: uuid.UUID, data: ChangeStatusRequest) -> TenantDetail:
        """Bloqueos manuales (P7): activo, bloqueo suave (sólo lectura) o bloqueo total."""
        tenant = await self._tenant_or_404(tenant_id)
        if tenant.status == data.status:
            raise _unprocessable("El comercio ya está en ese estado.")
        previous = tenant.status
        tenant.status = data.status
        await self.audit.append(
            AuditAction.STATUS_CHANGED,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="tenant",
            target_id=str(tenant_id),
            reason=data.reason,
            details={"de": previous.value, "a": data.status.value},
            meta=self.meta,
        )
        await self.db.commit()
        return await self._detail(tenant_id)

    async def change_plan(self, tenant_id: uuid.UUID, data: ChangePlanRequest) -> TenantDetail:
        tenant = await self._tenant_or_404(tenant_id)
        if tenant.plan_id == data.plan:
            raise _unprocessable("El comercio ya tiene ese plan.")
        limit = PLAN_USER_LIMITS.get(data.plan, 2)
        active_users = await self.reader.count_active_users(tenant_id)
        if active_users > limit:
            raise _unprocessable(
                f"El plan admite {limit} usuarios y el comercio tiene {active_users} activos. "
                "Primero deben dar de baja a alguien."
            )
        previous = tenant.plan_id
        tenant.plan_id = data.plan
        await self.audit.append(
            AuditAction.PLAN_CHANGED,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="tenant",
            target_id=str(tenant_id),
            reason=data.reason,
            details={
                "de": previous.value,
                "a": data.plan.value,
                "mensualidad_mxn": str(AVAILABLE_PLANS[data.plan].monthly_price_mxn),
            },
            meta=self.meta,
        )
        await self.db.commit()
        return await self._detail(tenant_id)

    async def grant_courtesy_month(self, tenant_id: uuid.UUID, data: CourtesyRequest) -> TenantDetail:
        """Un mes sin costo: factura pagada de $0 que sigue al último periodo pagado."""
        tenant = await self._tenant_or_404(tenant_id)
        last_end = await self.reader.latest_period_end(tenant_id)
        today = datetime.now(timezone.utc).date()
        start = max(today, last_end + timedelta(days=1)) if last_end else today
        end = _add_one_month(start) - timedelta(days=1)

        await set_tenant_context(self.db, tenant_id)
        invoice = SubscriptionInvoice(
            tenant_id=tenant_id,
            plan=tenant.plan_id,
            amount_mxn=Decimal("0.00"),
            payment_method=SaasPaymentMethod.COURTESY,
            status=SubscriptionInvoiceStatus.PAID,
            period_start=start,
            period_end=end,
            paid_at=datetime.now(timezone.utc),
        )
        self.db.add(invoice)
        reactivated = False
        if tenant.status != TenantStatus.ACTIVE:
            tenant.status = TenantStatus.ACTIVE
            reactivated = True
        await self.db.flush()

        await self.audit.append(
            AuditAction.COURTESY_GRANTED,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="invoice",
            target_id=str(invoice.id),
            reason=data.reason,
            details={"periodo": f"{start} a {end}", "plan": tenant.plan_id.value, "reactivado": reactivated},
            meta=self.meta,
        )
        await self.db.commit()
        return await self._detail(tenant_id)

    # ── Métricas ───────────────────────────────────────────────────────────

    async def metrics(self) -> PlatformMetrics:
        by_status: Dict[TenantStatus, int] = {s: 0 for s in TenantStatus}
        by_plan: Dict[TenantPlan, int] = {p: 0 for p in TenantPlan}
        mrr = Decimal("0.00")
        total = 0
        for tenant_status, plan, count in await self.reader.tenants_by_status_and_plan():
            by_status[tenant_status] += count
            by_plan[plan] += count
            total += count
            if tenant_status != TenantStatus.HARD_LOCK:
                mrr += AVAILABLE_PLANS[plan].monthly_price_mxn * count
        open_count, open_amount = await self.reader.open_invoices_totals()
        return PlatformMetrics(
            mrr_mxn=mrr,
            tenants_total=total,
            tenants_by_status=by_status,
            tenants_by_plan=by_plan,
            signups_last_30_days=await self.reader.signups_since(
                datetime.now(timezone.utc) - timedelta(days=30)
            ),
            open_invoices=open_count,
            open_invoices_amount_mxn=open_amount,
        )

    # ── Bitácora ───────────────────────────────────────────────────────────

    async def audit_page(
        self,
        tenant_id: Optional[uuid.UUID],
        operator_id: Optional[uuid.UUID],
        action: Optional[str],
        limit: int,
        offset: int,
    ) -> AuditPage:
        rows, total = await self.audit.list(
            tenant_id=tenant_id,
            operator_id=operator_id,
            actions=[action] if action else None,
            limit=limit,
            offset=offset,
        )
        return AuditPage(items=await self._audit_reads(rows), total=total)

    async def verify_audit_chain(self) -> ChainVerification:
        intact, checked, broken = await self.audit.verify_chain()
        return ChainVerification(intact=intact, checked=checked, broken_at_id=broken)

    # ── Apoyo ──────────────────────────────────────────────────────────────

    async def _tenant_or_404(self, tenant_id: uuid.UUID) -> Tenant:
        tenant = await self.reader.get_tenant(tenant_id)
        if tenant is None:
            raise _not_found()
        return tenant

    async def _audit_reads(self, rows: List[PlatformAuditLog]) -> List[AuditEntryRead]:
        names = await self.operators.names_by_id(list({r.operator_id for r in rows if r.operator_id}))
        return [
            AuditEntryRead(
                id=r.id,
                occurred_at=r.occurred_at,
                operator_id=r.operator_id,
                operator_name=names.get(r.operator_id),
                action=r.action,
                target_tenant_id=r.target_tenant_id,
                target_type=r.target_type,
                target_id=r.target_id,
                reason=r.reason,
                details=r.details or {},
                ip_address=r.ip_address,
            )
            for r in rows
        ]
