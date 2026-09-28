"""
Acciones del Centro de soporte (P15–P22). Cada una con motivo, en la bitácora
en la misma transacción que el cambio, y visible al Dueño (P8).

1. Recuperación asistida (P16/P21/P22): el operador valida al dueño y el código
   sale **directo a su correo**; la respuesta sólo trae el correo enmascarado.
2. Regalar días (P17): extiende `paid_until` por `grant_period`.
3. Suspender por abuso / levantar (P17): bloqueo propio que ni un pago levanta.
4. Exportar sus datos (P18): el archivo va al correo del dueño en segundo plano.
5. Eliminar la tienda (P4/P18): la pide un fundador y la aprueba **otro**.
"""
import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy import select

from app.core.config.settings import settings
from app.core.database.session import AsyncSessionLocal
from app.core.email.sender import EmailDeliveryError, send_email
from app.core.email.templates import data_export_email, login_code_email, store_deleted_email
from app.modules.auth_tenancy.domain.login_code import LoginCodeOrigin
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantLockReason, TenantStatus
from app.modules.auth_tenancy.domain.user import User
from app.modules.auth_tenancy.services.login_code_service import LoginCodeService, mask_email
from app.modules.core_admin.services.tenant_data import build_tenant_export, purge_tenant
from app.modules.platform_admin.domain.audit_log import AuditAction, PlatformAuditLog
from app.modules.platform_admin.domain.support import (
    ApprovalKind,
    ApprovalStatus,
    ExportStatus,
    PlatformApprovalRequest,
    PlatformExportJob,
)
from app.modules.platform_admin.repositories.audit_repository import AuditRepository, RequestMeta
from app.modules.platform_admin.repositories.operator_repository import OperatorRepository
from app.modules.platform_admin.repositories.platform_read_repository import PlatformReadRepository
from app.modules.platform_admin.schemas.platform_schemas import (
    ApprovalDecisionRequest,
    ApprovalRead,
    AssistedRecoveryRequest,
    AssistedRecoveryResponse,
    DeletionRequest,
    ExportJobRead,
    ExportRequest,
    GiftDaysRequest,
    LiftSuspensionRequest,
    OwnerPreview,
    OwnerPreviewRequest,
    SuspendRequest,
    TenantDetail,
)
from app.modules.platform_admin.services.platform_admin_service import (
    PlatformAdminService,
    approval_read,
    export_read,
    not_found,
)
from app.modules.platform_admin.services.tenant_activity import describe
from app.modules.saas_billing.services.entitlement import (
    EntitlementState,
    SubscriptionSource,
    entitlement_state,
    grant_period,
)

logger = logging.getLogger(__name__)
SYSTEM_META = RequestMeta(ip_address="sistema", user_agent="exportación de datos")

# Una exportación PENDING más vieja que esto se considera atascada (el proceso murió)
EXPORT_STALE_AFTER = timedelta(minutes=30)


def _unprocessable(detail: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=detail)


def _conflict(detail: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail)


def _gift_until(tenant: Tenant, days: int, now: datetime) -> datetime:
    base = tenant.paid_until if tenant.paid_until and tenant.paid_until > now else now
    return base + timedelta(days=days)


class SupportService(PlatformAdminService):

    # ── 1. Recuperación asistida ───────────────────────────────────────────

    async def assisted_recovery(self, tenant_id: uuid.UUID, data: AssistedRecoveryRequest) -> AssistedRecoveryResponse:
        tenant = await self.tenant_or_404(tenant_id)
        missing = [label for label, ok in (
            ("nombre de la tienda", data.checks.store_name),
            ("correo", data.checks.owner_email),
            ("fecha de alta", data.checks.signup_date),
            ("empleados", data.checks.employees),
        ) if not ok]
        if missing:
            raise _unprocessable(
                "Completa la validación antes de enviar el código. Falta confirmar: " + ", ".join(missing) + "."
            )
        order_id = (data.google_order_id or "").strip() or None
        if tenant.subscription_source == SubscriptionSource.GOOGLE_PLAY.value and not order_id:
            raise _unprocessable("Esta tienda paga con Google Play: pide el número de orden (GPA.…) y escríbelo.")
        owner = await self.reader.get_owner(tenant_id)
        if owner is None:
            raise _unprocessable("La tienda no tiene un dueño activo a quien enviarle el código.")

        code, expires_at = await LoginCodeService(self.db).issue(owner, LoginCodeOrigin.ASSISTED, self.operator.id)
        masked = mask_email(owner.email)
        await self.audit.append(
            AuditAction.ASSISTED_RECOVERY_SENT,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="user",
            target_id=str(owner.id),
            reason=data.reason,
            details={
                "correo": masked,
                "orden_google": order_id,
                "validacion": data.checks.model_dump(),
                "vence": expires_at.isoformat(),
            },
            meta=self.meta,
        )
        # El correo sale antes del commit: si el proveedor falla, no queda ni
        # código ni registro de un envío que no ocurrió. (Si el commit fallara
        # después, el código enviado no sirve: su hash nunca se guardó.)
        try:
            await send_email(login_code_email(owner.email, owner.full_name, code, expires_at, assisted=True))
        except EmailDeliveryError:
            await self.db.rollback()
            logger.exception("No se pudo enviar el código de recuperación asistida.")
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="No se pudo enviar el correo. No se generó ningún código; intenta de nuevo en unos minutos.",
            )
        await self.db.commit()
        return AssistedRecoveryResponse(sent_to=masked, expires_at=expires_at)

    # ── 2. Regalar días ────────────────────────────────────────────────────

    async def gift_days(self, tenant_id: uuid.UUID, data: GiftDaysRequest) -> TenantDetail:
        """
        Suma días sobre lo pagado (o desde hoy si ya venció). Con Google Play,
        además hay que posponer el cobro en Google (`subscriptions.defer`) por
        esta misma ruta: se conecta el día de la integración; por eso se
        conserva la fuente GOOGLE_PLAY y su gracia.
        """
        tenant = await self.tenant_or_404(tenant_id)
        now = datetime.now(timezone.utc)
        until = _gift_until(tenant, data.days, now)
        source = (
            SubscriptionSource.GOOGLE_PLAY
            if tenant.subscription_source == SubscriptionSource.GOOGLE_PLAY.value
            else SubscriptionSource.COURTESY
        )
        previous_until = tenant.paid_until
        reactivated = grant_period(tenant, until, source)
        await self.audit.append(
            AuditAction.DAYS_GIFTED,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="tenant",
            target_id=str(tenant_id),
            reason=data.reason,
            details={
                "dias": data.days,
                "vigente_antes": previous_until.isoformat() if previous_until else None,
                "vigente_hasta": until.isoformat(),
                "reactivado": reactivated,
            },
            meta=self.meta,
        )
        await self.db.commit()
        return await self.detail(tenant_id)

    # ── 3. Suspender por abuso / levantar ──────────────────────────────────

    async def suspend(self, tenant_id: uuid.UUID, data: SuspendRequest) -> TenantDetail:
        tenant = await self.tenant_or_404(tenant_id)
        if tenant.lock_reason == TenantLockReason.ABUSE.value:
            raise _unprocessable("La tienda ya está suspendida por soporte.")
        previous = tenant.status
        tenant.status = TenantStatus.HARD_LOCK
        tenant.lock_reason = TenantLockReason.ABUSE.value
        await self.audit.append(
            AuditAction.ABUSE_SUSPENDED,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="tenant",
            target_id=str(tenant_id),
            reason=data.reason,
            details={"de": previous.value, "a": TenantStatus.HARD_LOCK.value},
            meta=self.meta,
        )
        await self.db.commit()
        return await self.detail(tenant_id)

    async def lift_suspension(self, tenant_id: uuid.UUID, data: LiftSuspensionRequest) -> TenantDetail:
        """
        Vuelve a activa; si mientras tanto su suscripción venció y el ciclo está
        encendido, queda suspendida por falta de pago (lo que habría pasado sin
        la suspensión), no activa gratis.
        """
        tenant = await self.tenant_or_404(tenant_id)
        if tenant.lock_reason != TenantLockReason.ABUSE.value:
            raise _unprocessable("La tienda no está suspendida por soporte: no hay nada que levantar.")
        expired = (
            settings.SUBSCRIPTION_ENFORCEMENT_ENABLED
            and entitlement_state(tenant) == EntitlementState.VENCIDA
        )
        if expired:
            tenant.status = TenantStatus.HARD_LOCK
            tenant.lock_reason = TenantLockReason.NONPAYMENT.value
        else:
            tenant.status = TenantStatus.ACTIVE
            tenant.lock_reason = None
        await self.audit.append(
            AuditAction.ABUSE_LIFTED,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="tenant",
            target_id=str(tenant_id),
            reason=data.reason,
            details={"a": tenant.status.value, "vencida": expired},
            meta=self.meta,
        )
        await self.db.commit()
        return await self.detail(tenant_id)

    # ── 4. Exportar sus datos ──────────────────────────────────────────────

    async def request_export(self, tenant_id: uuid.UUID, data: ExportRequest) -> ExportJobRead:
        """Registra el pedido; quien llama agenda `run_export_job` en segundo plano."""
        await self.tenant_or_404(tenant_id)
        owner = await self.reader.get_owner(tenant_id)
        if owner is None:
            raise _unprocessable("La tienda no tiene un dueño activo a quien enviarle sus datos.")
        now = datetime.now(timezone.utc)
        running = (await self.db.execute(
            select(PlatformExportJob).where(
                PlatformExportJob.tenant_id == tenant_id,
                PlatformExportJob.status == ExportStatus.PENDING,
                PlatformExportJob.created_at > now - EXPORT_STALE_AFTER,
            )
        )).scalar_one_or_none()
        if running is not None:
            raise _conflict("Ya hay una exportación en proceso para esta tienda.")

        job = PlatformExportJob(tenant_id=tenant_id, requested_by=self.operator.id, status=ExportStatus.PENDING)
        self.db.add(job)
        await self.db.flush()
        await self.audit.append(
            AuditAction.DATA_EXPORT_REQUESTED,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="export",
            target_id=str(job.id),
            reason=data.reason,
            details={"correo": mask_email(owner.email)},
            meta=self.meta,
        )
        await self.db.commit()
        await self.db.refresh(job)
        return export_read(job, {self.operator.id: self.operator.full_name})

    # ── 5. Eliminar la tienda (dos personas) ───────────────────────────────

    async def request_deletion(self, tenant_id: uuid.UUID, data: DeletionRequest) -> ApprovalRead:
        tenant = await self.tenant_or_404(tenant_id)
        if data.confirm_slug.strip() != tenant.slug:
            raise _unprocessable(f"Para confirmar escribe exactamente el slug de la tienda: {tenant.slug}")
        now = datetime.now(timezone.utc)
        pending = await self._pending_deletion(tenant_id)
        if pending is not None:
            if pending.expires_at > now:
                raise _conflict("Ya hay una eliminación de esta tienda esperando la segunda aprobación.")
            pending.status = ApprovalStatus.CANCELLED
            pending.decision_reason = "Venció sin segunda aprobación."
            pending.decided_at = now
            await self.db.flush()

        request = PlatformApprovalRequest(
            kind=ApprovalKind.TENANT_DELETION,
            tenant_id=tenant_id,
            tenant_name=tenant.name,
            requested_by=self.operator.id,
            reason=data.reason,
            status=ApprovalStatus.PENDING,
            expires_at=now + timedelta(hours=settings.TENANT_DELETION_APPROVAL_HOURS),
        )
        self.db.add(request)
        await self.db.flush()
        await self.audit.append(
            AuditAction.TENANT_DELETION_REQUESTED,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="approval",
            target_id=str(request.id),
            reason=data.reason,
            details={"tienda": tenant.name, "slug": tenant.slug, "vence": request.expires_at.isoformat()},
            meta=self.meta,
        )
        await self.db.commit()
        await self.db.refresh(request)
        return approval_read(request, {self.operator.id: self.operator.full_name}, now)

    async def approve_deletion(self, request_id: uuid.UUID, data: ApprovalDecisionRequest) -> ApprovalRead:
        """La segunda persona aprueba y el borrado ocurre en esa misma transacción (irreversible)."""
        request = await self._approval_or_404(request_id)
        now = datetime.now(timezone.utc)
        if request.status != ApprovalStatus.PENDING:
            raise _unprocessable("Esta solicitud ya se resolvió.")
        if request.expires_at <= now:
            raise _unprocessable("La solicitud venció sin segunda aprobación. Si aún procede, hay que pedirla de nuevo.")
        if request.requested_by == self.operator.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="La eliminación la aprueba otro fundador, no quien la pidió.",
            )
        exporting = (await self.db.execute(
            select(PlatformExportJob.id).where(
                PlatformExportJob.tenant_id == request.tenant_id,
                PlatformExportJob.status == ExportStatus.PENDING,
                PlatformExportJob.created_at > now - EXPORT_STALE_AFTER,
            )
        )).first()
        if exporting is not None:
            raise _conflict("Hay una exportación de sus datos en proceso: espera a que llegue antes de eliminar.")

        tenant = await self.reader.get_tenant(request.tenant_id)
        if tenant is None:
            raise not_found("La tienda ya no existe.")
        owner: Optional[User] = await self.reader.get_owner(request.tenant_id)
        owner_contact = (owner.email, owner.full_name) if owner else None

        removed = await purge_tenant(self.db, request.tenant_id)
        request.status = ApprovalStatus.APPROVED
        request.decided_by = self.operator.id
        request.decided_at = now
        request.decision_reason = data.reason
        names = await self.operators.names_by_id([request.requested_by, self.operator.id])
        # Tras borrar sólo queda en la bitácora el nombre y el slug (sin datos personales)
        await self.audit.append(
            AuditAction.TENANT_DELETED,
            operator_id=self.operator.id,
            target_tenant_id=request.tenant_id,
            target_type="approval",
            target_id=str(request.id),
            reason=data.reason,
            details={
                "tienda": request.tenant_name,
                "slug": tenant.slug,
                "pedida_por": names.get(request.requested_by),
                "motivo_de_la_solicitud": request.reason,
                "renglones_borrados": sum(removed.values()),
            },
            meta=self.meta,
        )
        await self.db.commit()

        if owner_contact:
            try:
                await send_email(store_deleted_email(owner_contact[0], owner_contact[1], request.tenant_name))
            except EmailDeliveryError:
                logger.exception("No se pudo avisar al dueño de la eliminación de su tienda.")
        return approval_read(request, names, now)

    async def cancel_deletion(self, request_id: uuid.UUID, data: ApprovalDecisionRequest) -> ApprovalRead:
        """Cualquiera de los dos puede cancelarla (quien la pidió se arrepiente o el otro no está de acuerdo)."""
        request = await self._approval_or_404(request_id)
        if request.status != ApprovalStatus.PENDING:
            raise _unprocessable("Esta solicitud ya se resolvió.")
        now = datetime.now(timezone.utc)
        request.status = ApprovalStatus.CANCELLED
        request.decided_by = self.operator.id
        request.decided_at = now
        request.decision_reason = data.reason
        await self.audit.append(
            AuditAction.TENANT_DELETION_CANCELLED,
            operator_id=self.operator.id,
            target_tenant_id=request.tenant_id,
            target_type="approval",
            target_id=str(request.id),
            reason=data.reason,
            details={"tienda": request.tenant_name},
            meta=self.meta,
        )
        await self.db.commit()
        names = await self.operators.names_by_id([request.requested_by, self.operator.id])
        return approval_read(request, names, now)

    async def _pending_deletion(self, tenant_id: uuid.UUID) -> Optional[PlatformApprovalRequest]:
        return (await self.db.execute(
            select(PlatformApprovalRequest).where(
                PlatformApprovalRequest.tenant_id == tenant_id,
                PlatformApprovalRequest.kind == ApprovalKind.TENANT_DELETION,
                PlatformApprovalRequest.status == ApprovalStatus.PENDING,
            )
        )).scalar_one_or_none()

    async def _approval_or_404(self, request_id: uuid.UUID) -> PlatformApprovalRequest:
        request = (await self.db.execute(
            select(PlatformApprovalRequest).where(PlatformApprovalRequest.id == request_id)
        )).scalar_one_or_none()
        if request is None:
            raise not_found("Solicitud no encontrada.")
        return request

    # ── "Así lo verá la tienda" ────────────────────────────────────────────

    async def owner_preview(self, tenant_id: uuid.UUID, data: OwnerPreviewRequest) -> OwnerPreview:
        """El mismo texto de "Actividad de soporte" que recibirá el dueño, calculado sin cambiar nada."""
        tenant = await self.tenant_or_404(tenant_id)
        now = datetime.now(timezone.utc)
        details: dict = {}
        if data.action == AuditAction.DAYS_GIFTED:
            days = data.days or 1
            details = {
                "dias": days,
                "vigente_hasta": _gift_until(tenant, days, now).isoformat(),
                "reactivado": tenant.status != TenantStatus.ACTIVE and tenant.lock_reason != TenantLockReason.ABUSE.value,
            }
        elif data.action in (AuditAction.ASSISTED_RECOVERY_SENT, AuditAction.DATA_EXPORT_REQUESTED):
            owner = await self.reader.get_owner(tenant_id)
            details = {"correo": mask_email(owner.email) if owner else "tu correo"}
        elif data.action == AuditAction.ABUSE_LIFTED:
            details = {"a": TenantStatus.ACTIVE.value}
        entry = PlatformAuditLog(action=data.action, details=details)
        return OwnerPreview(
            summary=describe(entry),
            reason=(data.reason or "").strip() or None,
            by=f"Soporte Nexus · {self.operator.full_name}",
        )


# ── Exportación en segundo plano ───────────────────────────────────────────

async def run_export_job(job_id: uuid.UUID, session_factory=None) -> None:
    """
    Arma el ZIP leyendo como el comercio, lo manda al correo del dueño y deja
    constancia (SENT/FAILED) en el trabajo y en la bitácora como "sistema".
    Corre con su propia sesión: la de la petición ya se cerró.
    """
    factory = session_factory or AsyncSessionLocal
    async with factory() as db:
        job = (await db.execute(select(PlatformExportJob).where(PlatformExportJob.id == job_id))).scalar_one_or_none()
        if job is None or job.status != ExportStatus.PENDING:
            return
        reader = PlatformReadRepository(db)
        owner = await reader.get_owner(job.tenant_id)
        tenant = await reader.get_tenant(job.tenant_id)
        error: Optional[str] = None
        size = None
        if owner is None or tenant is None:
            error = "La tienda ya no tiene un dueño activo."
        else:
            owner_email, owner_name, store_name = owner.email, owner.full_name, tenant.name
            try:
                filename, content, _ = await build_tenant_export(db, job.tenant_id)
                size = len(content)
                limit = settings.EMAIL_MAX_ATTACHMENT_MB * 1024 * 1024
                if size > limit:
                    error = (
                        f"El archivo pesa {size / 1024 / 1024:.1f} MB y el correo admite "
                        f"{settings.EMAIL_MAX_ATTACHMENT_MB} MB."
                    )
                else:
                    await send_email(data_export_email(owner_email, owner_name, store_name, filename, content))
            except EmailDeliveryError as err:
                error = f"El proveedor de correo lo rechazó: {err}"[:500]
            except Exception as err:  # el trabajo no puede quedarse PENDING para siempre
                logger.exception("Falló la exportación de datos.")
                error = f"Error al generar el archivo ({err.__class__.__name__})."
                # La transacción pudo quedar abortada: se descarta y se vuelve a leer el trabajo
                await db.rollback()
                job = (await db.execute(
                    select(PlatformExportJob)
                    .where(PlatformExportJob.id == job_id)
                    .execution_options(populate_existing=True)
                )).scalar_one()

        job.status = ExportStatus.FAILED if error else ExportStatus.SENT
        job.error = error
        job.size_bytes = size
        job.finished_at = datetime.now(timezone.utc)
        await AuditRepository(db).append(
            AuditAction.DATA_EXPORT_FAILED if error else AuditAction.DATA_EXPORT_SENT,
            target_tenant_id=job.tenant_id,
            target_type="export",
            target_id=str(job.id),
            details=(
                {"error": error} if error
                else {"correo": mask_email(owner_email), "bytes": size}
            ),
            meta=SYSTEM_META,
        )
        await db.commit()
