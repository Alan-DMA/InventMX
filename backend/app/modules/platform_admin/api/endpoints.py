"""
API del panel de plataforma: `/api/v1/platform/*` (Fase 1).

Todo, salvo los tres pasos de acceso, exige un token de plataforma. Ninguna
ruta de aquí acepta un token de comercio (otra llave de firma y otra audiencia).
"""
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import get_db
from app.modules.auth_tenancy.domain.tenant import TenantPlan, TenantStatus
from app.modules.platform_admin.domain.operator import PlatformOperator
from app.modules.platform_admin.repositories.audit_repository import RequestMeta
from app.modules.platform_admin.schemas.platform_schemas import (
    AuditPage,
    ChainVerification,
    ChangePlanRequest,
    ChangeStatusRequest,
    ConfirmPaymentRequest,
    CourtesyRequest,
    InvoicePage,
    LoginRequest,
    LoginResponse,
    OperatorRead,
    PlatformMetrics,
    RecoveryLoginRequest,
    SessionResponse,
    TenantDetail,
    TenantPage,
    VerifyTotpRequest,
)
from app.modules.platform_admin.security.deps import get_current_operator, request_meta
from app.modules.platform_admin.services.platform_admin_service import PlatformAdminService
from app.modules.platform_admin.services.platform_auth_service import PlatformAuthService

router = APIRouter(prefix="/platform", tags=["Plataforma (fundadores)"])


def _service(
    operator: PlatformOperator = Depends(get_current_operator),
    meta: RequestMeta = Depends(request_meta),
    db: AsyncSession = Depends(get_db),
) -> PlatformAdminService:
    return PlatformAdminService(db, operator, meta)


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


# ── Métricas ───────────────────────────────────────────────────────────────

@router.get("/metrics", response_model=PlatformMetrics, summary="MRR, comercios por estado y pagos pendientes")
async def metrics(service: PlatformAdminService = Depends(_service)):
    return await service.metrics()


# ── Comercios ──────────────────────────────────────────────────────────────

@router.get("/tenants", response_model=TenantPage, summary="Directorio de comercios (sólo metadatos)")
async def list_tenants(
    status: Optional[TenantStatus] = Query(None),
    plan: Optional[TenantPlan] = Query(None),
    q: Optional[str] = Query(None, max_length=100, description="Nombre, slug o correo del dueño"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    service: PlatformAdminService = Depends(_service),
):
    return await service.list_tenants(status, plan, q, limit, offset)


@router.get("/tenants/{tenant_id}", response_model=TenantDetail, summary="Ficha de un comercio")
async def get_tenant(tenant_id: uuid.UUID, service: PlatformAdminService = Depends(_service)):
    """Abrirla queda en la bitácora."""
    return await service.get_tenant_detail(tenant_id)


@router.post("/tenants/{tenant_id}/payments/confirm", response_model=TenantDetail, summary="Confirmar un pago manual")
async def confirm_payment(
    tenant_id: uuid.UUID,
    data: ConfirmPaymentRequest,
    service: PlatformAdminService = Depends(_service),
):
    """Efectivo o SPEI verificado en el banco. Reactiva si ya no queda nada vencido."""
    return await service.confirm_payment(tenant_id, data)


@router.post("/tenants/{tenant_id}/status", response_model=TenantDetail, summary="Cambiar el estado (bloqueo manual)")
async def change_status(
    tenant_id: uuid.UUID,
    data: ChangeStatusRequest,
    service: PlatformAdminService = Depends(_service),
):
    return await service.change_status(tenant_id, data)


@router.post("/tenants/{tenant_id}/plan", response_model=TenantDetail, summary="Cambiar el plan")
async def change_plan(
    tenant_id: uuid.UUID,
    data: ChangePlanRequest,
    service: PlatformAdminService = Depends(_service),
):
    """Rechaza bajar a un plan cuyo límite de usuarios el comercio ya excede."""
    return await service.change_plan(tenant_id, data)


@router.post("/tenants/{tenant_id}/courtesy", response_model=TenantDetail, summary="Regalar un mes")
async def grant_courtesy(
    tenant_id: uuid.UUID,
    data: CourtesyRequest,
    service: PlatformAdminService = Depends(_service),
):
    return await service.grant_courtesy_month(tenant_id, data)


# ── Pagos pendientes ───────────────────────────────────────────────────────

@router.get("/invoices/open", response_model=InvoicePage, summary="Bandeja de pagos por conciliar")
async def open_invoices(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    service: PlatformAdminService = Depends(_service),
):
    return await service.list_open_invoices(limit, offset)


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
