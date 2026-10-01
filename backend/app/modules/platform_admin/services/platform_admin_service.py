"""
Comercios, ficha, métricas y bitácora del panel (Fase 1 → Centro de soporte).

Reglas que atraviesan todo:
- Sólo metadatos (P2): nada de ventas, productos, clientes ni cajas.
- El cobro lo hace Google Play (P13): vencer, gracia y suspensión por falta de
  pago son información, no acciones (P15). Confirmar pagos, cambiar plan y la
  cortesía con factura $0 se retiraron (P19).
- Las acciones de soporte viven en `support_service.py`.
"""
import uuid
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config.settings import settings
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan, TenantStatus
from app.modules.auth_tenancy.services.user_service import PLAN_USER_LIMITS
from app.modules.platform_admin.services.support_session import open_sessions
from app.modules.platform_admin.services.audit_text import operator_summary
from app.modules.platform_admin.domain.audit_log import AuditAction, PlatformAuditLog
from app.modules.platform_admin.domain.operator import PlatformOperator
from app.modules.platform_admin.domain.support import (
    ApprovalKind,
    ApprovalStatus,
    PlatformApprovalRequest,
    PlatformExportJob,
)
from app.modules.platform_admin.repositories.audit_repository import AuditRepository, RequestMeta
from app.modules.platform_admin.repositories.operator_repository import OperatorRepository
from app.modules.platform_admin.repositories.platform_read_repository import PlatformReadRepository
from app.modules.platform_admin.schemas.platform_schemas import (
    ApprovalRead,
    AuditEntryRead,
    AuditPage,
    ChainVerification,
    DiagnosticUser,
    DiagnosticWarehouse,
    ExportJobRead,
    PlatformMetrics,
    SupportState,
    TenantDetail,
    TenantDiagnostics,
    TenantPage,
    TenantSummary,
)
from app.modules.saas_billing.services.entitlement import entitlement_state, grace_until


def not_found(detail: str = "Comercio no encontrado.") -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=detail)


def summary_from_row(row) -> TenantSummary:
    tenant: Tenant = row[0]
    return TenantSummary(
        id=tenant.id,
        name=tenant.name,
        slug=tenant.slug,
        plan=tenant.plan_id,
        status=tenant.status,
        lock_reason=tenant.lock_reason,
        created_at=tenant.created_at,
        owner_name=row.owner_name,
        owner_email=row.owner_email,
        users_count=int(row.users_count or 0),
        users_limit=PLAN_USER_LIMITS.get(tenant.plan_id, 2),
        last_activity_at=row.last_activity_at,
        paid_until=tenant.paid_until,
        grace_until=grace_until(tenant),
        entitlement=entitlement_state(tenant).value,
        subscription_source=tenant.subscription_source,
    )


def export_read(job: PlatformExportJob, names: Dict[uuid.UUID, str]) -> ExportJobRead:
    return ExportJobRead(
        id=job.id,
        tenant_id=job.tenant_id,
        status=job.status,
        error=job.error,
        size_bytes=job.size_bytes,
        requested_by_name=names.get(job.requested_by),
        created_at=job.created_at,
        finished_at=job.finished_at,
    )


def approval_read(request: PlatformApprovalRequest, names: Dict[uuid.UUID, str], now: datetime) -> ApprovalRead:
    return ApprovalRead(
        id=request.id,
        kind=request.kind,
        tenant_id=request.tenant_id,
        tenant_name=request.tenant_name,
        requested_by=request.requested_by,
        requested_by_name=names.get(request.requested_by),
        reason=request.reason,
        status=request.status,
        decided_by_name=names.get(request.decided_by) if request.decided_by else None,
        decision_reason=request.decision_reason,
        decided_at=request.decided_at,
        expires_at=request.expires_at,
        created_at=request.created_at,
        expired=request.status == ApprovalStatus.PENDING and request.expires_at <= now,
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
        return TenantPage(items=[summary_from_row(r) for r in rows], total=total)

    async def get_tenant_detail(self, tenant_id: uuid.UUID) -> TenantDetail:
        """Abrir la ficha de un comercio queda registrado (sin motivo: es sólo lectura)."""
        if await self.reader.get_tenant(tenant_id) is None:
            raise not_found()
        await self.audit.append(
            AuditAction.TENANT_VIEWED,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="tenant",
            target_id=str(tenant_id),
            meta=self.meta,
        )
        await self.db.commit()
        return await self.detail(tenant_id)

    async def detail(self, tenant_id: uuid.UUID) -> TenantDetail:
        """La ficha sin registrar otra lectura (las acciones la devuelven así)."""
        row = await self.reader.get_tenant_summary(tenant_id)
        if row is None:
            raise not_found()
        tenant: Tenant = row[0]
        # Sin el ruido del feed: abrir la ficha no llena la actividad de "abrió la ficha"
        activity, _ = await self.audit.list(tenant_id=tenant_id, limit=30, exclude_actions=AuditAction.FEED_NOISE)
        return TenantDetail(
            **summary_from_row(row).model_dump(),
            suspension_reason=await self._suspension_reason(tenant),
            diagnostics=await self._diagnostics(tenant_id),
            support=await self._support_state(tenant_id),
            activity=await self.audit_reads(activity, store_name=tenant.name),
        )

    async def _suspension_reason(self, tenant: Tenant) -> Optional[str]:
        if tenant.lock_reason != "ABUSE":
            return None
        rows, _ = await self.audit.list(tenant_id=tenant.id, actions=[AuditAction.ABUSE_SUSPENDED], limit=1)
        return rows[0].reason if rows else None

    async def _diagnostics(self, tenant_id: uuid.UUID) -> TenantDiagnostics:
        return TenantDiagnostics(
            catalog_enabled=await self.reader.catalog_enabled(tenant_id),
            warehouses=[
                DiagnosticWarehouse(name=name, is_active=active, is_default=default)
                for name, active, default in await self.reader.diagnostic_warehouses(tenant_id)
            ],
            users=[
                DiagnosticUser(full_name=name, email=email, role=role, is_active=active, last_login_at=last)
                for name, email, role, active, last in await self.reader.diagnostic_users(tenant_id)
            ],
        )

    async def _support_state(self, tenant_id: uuid.UUID) -> SupportState:
        now = datetime.now(timezone.utc)
        grants = await self.reader.active_grants(now, tenant_id)
        codes = await self.reader.unused_assisted_codes(now, tenant_id)
        deletion = (await self.db.execute(
            select(PlatformApprovalRequest).where(
                PlatformApprovalRequest.tenant_id == tenant_id,
                PlatformApprovalRequest.kind == ApprovalKind.TENANT_DELETION,
                PlatformApprovalRequest.status == ApprovalStatus.PENDING,
            )
        )).scalar_one_or_none()
        export = (await self.db.execute(
            select(PlatformExportJob)
            .where(PlatformExportJob.tenant_id == tenant_id)
            .order_by(PlatformExportJob.created_at.desc())
            .limit(1)
        )).scalar_one_or_none()
        ids = [x for x in (
            deletion.requested_by if deletion else None,
            export.requested_by if export else None,
        ) if x]
        names = await self.operators.names_by_id(ids)
        return SupportState(
            access_granted_until=grants[0].expires_at if grants else None,
            assisted_code_until=codes[0].expires_at if codes else None,
            pending_deletion=approval_read(deletion, names, now) if deletion else None,
            last_export=export_read(export, names) if export else None,
            support_sessions=await open_sessions(self.db, tenant_id),
            support_access_since=grants[0].created_at if grants else None,
        )

    # ── Métricas ───────────────────────────────────────────────────────────

    async def metrics(self) -> PlatformMetrics:
        by_status: Dict[TenantStatus, int] = {s: 0 for s in TenantStatus}
        by_plan: Dict[TenantPlan, int] = {p: 0 for p in TenantPlan}
        total = 0
        for tenant_status, plan, count in await self.reader.tenants_by_status_and_plan():
            by_status[tenant_status] += count
            by_plan[plan] += count
            total += count
        return PlatformMetrics(
            tenants_total=total,
            tenants_by_status=by_status,
            tenants_by_plan=by_plan,
            signups_last_30_days=await self.reader.signups_since(
                datetime.now(timezone.utc) - timedelta(days=30)
            ),
            abuse_suspended=len(await self.reader.abuse_suspended_tenants()),
            # El ingreso real lo reporta Google Play; hasta integrarlo no se inventa una cifra
            revenue_connected=settings.SUBSCRIPTION_RENEWAL_CHANNEL == "GOOGLE_PLAY",
            monthly_revenue_mxn=None,
        )

    # ── Bitácora ───────────────────────────────────────────────────────────

    async def audit_page(
        self,
        tenant_id: Optional[uuid.UUID],
        operator_id: Optional[uuid.UUID],
        action: Optional[str],
        limit: int,
        offset: int,
        exclude_noise: bool = False,
    ) -> AuditPage:
        rows, total = await self.audit.list(
            tenant_id=tenant_id,
            operator_id=operator_id,
            actions=[action] if action else None,
            limit=limit,
            offset=offset,
            exclude_actions=AuditAction.FEED_NOISE if exclude_noise and not action else None,
        )
        return AuditPage(items=await self.audit_reads(rows), total=total)

    async def verify_audit_chain(self) -> ChainVerification:
        intact, checked, broken = await self.audit.verify_chain()
        return ChainVerification(intact=intact, checked=checked, broken_at_id=broken)

    # ── Apoyo ──────────────────────────────────────────────────────────────

    async def tenant_or_404(self, tenant_id: uuid.UUID) -> Tenant:
        tenant = await self.reader.get_tenant(tenant_id)
        if tenant is None:
            raise not_found()
        return tenant

    async def audit_reads(self, rows: List[PlatformAuditLog], store_name: Optional[str] = None) -> List[AuditEntryRead]:
        names = await self.operators.names_by_id(list({r.operator_id for r in rows if r.operator_id}))
        # Sin tienda fija (la bitácora general), cada renglón dice la suya; una
        # tienda eliminada conserva el nombre que guardó la bitácora (`tienda`)
        stores: Dict[uuid.UUID, str] = {}
        if store_name is None:
            ids = list({r.target_tenant_id for r in rows if r.target_tenant_id})
            stores = await self.reader.tenant_names(ids) if ids else {}
        return [
            AuditEntryRead(
                id=r.id,
                occurred_at=r.occurred_at,
                operator_id=r.operator_id,
                operator_name=names.get(r.operator_id),
                summary=operator_summary(r, names.get(r.operator_id), store_name or stores.get(r.target_tenant_id)),
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
