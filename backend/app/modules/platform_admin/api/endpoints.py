"""
API del panel de plataforma: `/api/v1/platform/*` (Fase 1 → Centro de soporte).

Todo, salvo los tres pasos de acceso, exige un token de plataforma. Ninguna
ruta de aquí acepta un token de comercio (otra llave de firma y otra audiencia).
Sin acciones de cobro (P19): confirmar pagos, cambiar plan y la cortesía con
factura $0 se retiraron; Google Play es la única fuente de cobro y plan.
"""
import uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, Query
from fastapi import status as http_status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config.settings import settings
from app.core.database.session import get_db
from app.modules.auth_tenancy.domain.tenant import TenantPlan, TenantStatus
from app.modules.platform_admin.domain.operator import PlatformOperator
from app.modules.platform_admin.repositories.audit_repository import RequestMeta
from app.modules.platform_admin.schemas.platform_schemas import (
    ApprovalDecisionRequest,
    ApprovalRead,
    AssistedRecoveryRequest,
    AssistedRecoveryResponse,
    AuditPage,
    ChainVerification,
    DeletionRequest,
    ExportJobRead,
    ExportRequest,
    Feed,
    GiftDaysRequest,
    LiftSuspensionRequest,
    LoginRequest,
    LoginResponse,
    OperatorRead,
    OwnerPreview,
    OwnerPreviewRequest,
    PlatformMetrics,
    RecoveryLoginRequest,
    SessionResponse,
    SuspendRequest,
    TenantDetail,
    TenantPage,
    VerifyTotpRequest,
)
from app.modules.platform_admin.security.deps import get_current_operator, request_meta
from app.modules.platform_admin.services.feed_service import FeedService
from app.modules.platform_admin.services.platform_admin_service import PlatformAdminService
from app.modules.platform_admin.services.platform_auth_service import PlatformAuthService
from app.modules.platform_admin.services.subscription_cycle import run_subscription_cycle
from app.modules.platform_admin.services.support_service import SupportService, run_export_job

router = APIRouter(prefix="/platform", tags=["Plataforma (fundadores)"])


def _service(
    operator: PlatformOperator = Depends(get_current_operator),
    meta: RequestMeta = Depends(request_meta),
    db: AsyncSession = Depends(get_db),
) -> PlatformAdminService:
    return PlatformAdminService(db, operator, meta)


def _support(
    operator: PlatformOperator = Depends(get_current_operator),
    meta: RequestMeta = Depends(request_meta),
    db: AsyncSession = Depends(get_db),
) -> SupportService:
    return SupportService(db, operator, meta)


def _feed(
    operator: PlatformOperator = Depends(get_current_operator),
    meta: RequestMeta = Depends(request_meta),
    db: AsyncSession = Depends(get_db),
) -> FeedService:
    return FeedService(db, operator, meta)


# ── Acceso ─────────────────────────────────────────────────────────────────

@router.post("/auth/login", response_model=LoginResponse, summary="Paso 1: correo y contraseña")
async def login(
    data: LoginRequest,
    meta: RequestMeta = Depends(request_meta),
    db: AsyncSession = Depends(get_db),
):
    """Devuelve un reto de 5 min; en el primer acceso, también el QR de vinculación."""
    return await PlatformAuthService(db).login(data.email, data.password, meta)


@router.post("/auth/verify", response_model=SessionResponse, summary="Paso 2: código de Google Authenticator")
async def verify(
    data: VerifyTotpRequest,
    meta: RequestMeta = Depends(request_meta),
    db: AsyncSession = Depends(get_db),
):
    """Abre la sesión (2 h, sin refresh). En la vinculación devuelve los códigos de recuperación una vez."""
    return await PlatformAuthService(db).verify_totp(data.challenge_token, data.code, meta)


@router.post("/auth/recover", response_model=SessionResponse, summary="Paso 2 alterno: código de recuperación")
async def recover(
    data: RecoveryLoginRequest,
    meta: RequestMeta = Depends(request_meta),
    db: AsyncSession = Depends(get_db),
):
    return await PlatformAuthService(db).login_with_recovery_code(data.challenge_token, data.recovery_code, meta)


@router.get("/auth/me", response_model=OperatorRead, summary="Operador en sesión")
async def me(operator: PlatformOperator = Depends(get_current_operator)):
    return operator


# ── Feed del día y métricas ────────────────────────────────────────────────

@router.get("/feed", response_model=Feed, summary="Requiere atención + lo que pasó")
async def feed(
    since: Optional[datetime] = Query(None, description="Desde (incluido). Por omisión, 3 días antes de `until`"),
    until: Optional[datetime] = Query(None, description="Hasta (excluido). Por omisión, ahora"),
    service: FeedService = Depends(_feed),
):
    """El cliente agrupa los eventos por día en su zona horaria; "Ver anteriores" pide el rango previo."""
    return await service.feed(since, until)


@router.get("/metrics", response_model=PlatformMetrics, summary="Tiendas por estado y plan, altas 30 días")
async def metrics(service: PlatformAdminService = Depends(_service)):
    return await service.metrics()


# ── Comercios ──────────────────────────────────────────────────────────────

@router.get("/tenants", response_model=TenantPage, summary="Buscador de tiendas (sólo metadatos)")
async def list_tenants(
    status: Optional[TenantStatus] = Query(None),
    plan: Optional[TenantPlan] = Query(None),
    q: Optional[str] = Query(None, max_length=100, description="Nombre, slug o correo del dueño"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    service: PlatformAdminService = Depends(_service),
):
    return await service.list_tenants(status, plan, q, limit, offset)


@router.get("/tenants/{tenant_id}", response_model=TenantDetail, summary="Ficha de la tienda")
async def get_tenant(tenant_id: uuid.UUID, service: PlatformAdminService = Depends(_service)):
    """Suscripción informativa, diagnóstico, lo que está en curso y actividad. Abrirla queda en la bitácora."""
    return await service.get_tenant_detail(tenant_id)


@router.post("/tenants/{tenant_id}/preview", response_model=OwnerPreview, summary="Así lo verá la tienda")
async def owner_preview(
    tenant_id: uuid.UUID,
    data: OwnerPreviewRequest,
    service: SupportService = Depends(_support),
):
    """El texto exacto que verá el dueño en "Actividad de soporte". No cambia nada ni se registra."""
    return await service.owner_preview(tenant_id, data)


# ── Acciones de soporte (todas con motivo, visibles al dueño) ──────────────

@router.post(
    "/tenants/{tenant_id}/assisted-recovery",
    response_model=AssistedRecoveryResponse,
    summary="Recuperación asistida: código al correo del dueño",
)
async def assisted_recovery(
    tenant_id: uuid.UUID,
    data: AssistedRecoveryRequest,
    service: SupportService = Depends(_support),
):
    """
    Exige la validación completa (y el número de orden si paga con Google Play).
    El código va directo al correo del dueño: la respuesta sólo trae el correo
    enmascarado y el vencimiento (24 h).
    """
    return await service.assisted_recovery(tenant_id, data)


@router.post("/tenants/{tenant_id}/gift-days", response_model=TenantDetail, summary="Regalar días")
async def gift_days(
    tenant_id: uuid.UUID,
    data: GiftDaysRequest,
    service: SupportService = Depends(_support),
):
    return await service.gift_days(tenant_id, data)


@router.post("/tenants/{tenant_id}/suspension", response_model=TenantDetail, summary="Suspender por abuso")
async def suspend(
    tenant_id: uuid.UUID,
    data: SuspendRequest,
    service: SupportService = Depends(_support),
):
    """Bloqueo propio de soporte: ni un pago ni un regalo de días lo levantan."""
    return await service.suspend(tenant_id, data)


@router.post("/tenants/{tenant_id}/suspension/lift", response_model=TenantDetail, summary="Levantar la suspensión")
async def lift_suspension(
    tenant_id: uuid.UUID,
    data: LiftSuspensionRequest,
    service: SupportService = Depends(_support),
):
    return await service.lift_suspension(tenant_id, data)


@router.post(
    "/tenants/{tenant_id}/export",
    response_model=ExportJobRead,
    status_code=http_status.HTTP_202_ACCEPTED,
    summary="Exportar sus datos al correo del dueño",
)
async def export_data(
    tenant_id: uuid.UUID,
    data: ExportRequest,
    background: BackgroundTasks,
    service: SupportService = Depends(_support),
):
    """Se genera en segundo plano y llega al correo del dueño; el panel sólo ve el estado (P2)."""
    job = await service.request_export(tenant_id, data)
    background.add_task(run_export_job, job.id)
    return job


@router.post(
    "/tenants/{tenant_id}/deletion",
    response_model=ApprovalRead,
    status_code=http_status.HTTP_201_CREATED,
    summary="Pedir la eliminación de la tienda (1 de 2)",
)
async def request_deletion(
    tenant_id: uuid.UUID,
    data: DeletionRequest,
    service: SupportService = Depends(_support),
):
    """Se confirma escribiendo el slug. La aprueba otro fundador antes de 72 h, o vence."""
    return await service.request_deletion(tenant_id, data)


@router.post("/approvals/{request_id}/approve", response_model=ApprovalRead, summary="Aprobar (2 de 2)")
async def approve(
    request_id: uuid.UUID,
    data: ApprovalDecisionRequest,
    service: SupportService = Depends(_support),
):
    """Sólo un fundador distinto del que la pidió. Borra la tienda y todos sus datos: irreversible."""
    return await service.approve_deletion(request_id, data)


@router.post("/approvals/{request_id}/cancel", response_model=ApprovalRead, summary="Cancelar una solicitud")
async def cancel(
    request_id: uuid.UUID,
    data: ApprovalDecisionRequest,
    service: SupportService = Depends(_support),
):
    return await service.cancel_deletion(request_id, data)


# ── Ciclo de suscripción ────────────────────────────────────────────────────

@router.get("/subscription-cycle/preview", summary="A quién suspendería hoy el ciclo (sin cambiar nada)")
async def subscription_cycle_preview(
    operator: PlatformOperator = Depends(get_current_operator),
    db: AsyncSession = Depends(get_db),
):
    """
    Vista previa para encender el ciclo sin sorpresas (P13): comercios en gracia
    y los que se suspenderían. No modifica nada aunque el ciclo esté encendido.
    """
    report = await run_subscription_cycle(db, enforce=False)
    return {
        "enforcement_enabled": settings.SUBSCRIPTION_ENFORCEMENT_ENABLED,
        "checked": report.checked,
        "in_grace": [vars(t) for t in report.in_grace],
        "would_suspend": [vars(t) for t in report.suspended],
    }


# ── Bitácora ───────────────────────────────────────────────────────────────

@router.get("/audit", response_model=AuditPage, summary="Bitácora de la plataforma")
async def audit(
    tenant_id: Optional[uuid.UUID] = Query(None),
    operator_id: Optional[uuid.UUID] = Query(None),
    action: Optional[str] = Query(None, max_length=60),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    service: PlatformAdminService = Depends(_service),
):
    return await service.audit_page(tenant_id, operator_id, action, limit, offset)


@router.get("/audit/verify", response_model=ChainVerification, summary="Verificar la cadena de la bitácora")
async def verify_audit(service: PlatformAdminService = Depends(_service)):
    """Recalcula los hashes: detecta cualquier renglón alterado por fuera de la aplicación."""
    return await service.verify_audit_chain()
