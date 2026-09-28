"""Esquemas del panel de plataforma (Fase 1 + Centro de soporte)."""
import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.modules.auth_tenancy.domain.tenant import TenantPlan, TenantStatus

# Motivo obligatorio de toda acción que cambia algo. El Dueño del comercio lo
# lee en "Actividad de soporte" (P8): se escribe para él, no como nota interna.
REASON_FIELD = Field(
    ...,
    min_length=10,
    max_length=500,
    description="Por qué se hace. Lo ve el Dueño del comercio en su app (transparencia, P8).",
)


class _WithReason(BaseModel):
    reason: str = REASON_FIELD

    @field_validator("reason")
    @classmethod
    def _strip(cls, value: str) -> str:
        cleaned = value.strip()
        if len(cleaned) < 10:
            raise ValueError("El motivo debe explicar la acción (mínimo 10 caracteres).")
        return cleaned


# ── Acceso ─────────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=1, max_length=200)


class LoginResponse(BaseModel):
    status: Literal["TOTP_REQUIRED", "ENROLLMENT_REQUIRED"]
    challenge_token: str
    # Sólo en la vinculación (primer acceso): QR y secreto para capturarlo a mano
    otpauth_uri: Optional[str] = None
    manual_secret: Optional[str] = None


class VerifyTotpRequest(BaseModel):
    challenge_token: str
    code: str = Field(..., min_length=6, max_length=10)


class RecoveryLoginRequest(BaseModel):
    challenge_token: str
    recovery_code: str = Field(..., min_length=10, max_length=20)


class OperatorRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    email: str
    full_name: str
    last_login_at: Optional[datetime] = None


class SessionResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int = Field(..., description="Segundos de vigencia; sin refresh")
    operator: OperatorRead
    # Sólo al vincular TOTP por primera vez: se muestran una vez y no se guardan en claro
    recovery_codes: Optional[List[str]] = None
    recovery_codes_remaining: int


# ── Comercios ──────────────────────────────────────────────────────────────

class TenantSummary(BaseModel):
    """Metadatos de un comercio: nada de su contenido (P2)."""
    id: uuid.UUID
    name: str
    slug: str
    plan: TenantPlan
    status: TenantStatus
    lock_reason: Optional[str] = Field(None, description="NONPAYMENT o ABUSE si está bloqueado")
    created_at: datetime
    owner_name: Optional[str] = None
    owner_email: Optional[str] = None
    users_count: int
    users_limit: int
    last_activity_at: Optional[datetime] = None
    # Vigencia prepago (informativa: la gestiona Google Play, P15)
    paid_until: Optional[datetime] = None
    grace_until: Optional[datetime] = None
    entitlement: str = "SIN_FECHA"
    subscription_source: Optional[str] = None


class TenantPage(BaseModel):
    items: List[TenantSummary]
    total: int


class AuditEntryRead(BaseModel):
    id: int
    occurred_at: datetime
    operator_id: Optional[uuid.UUID] = None
    operator_name: Optional[str] = None
    action: str
    target_tenant_id: Optional[uuid.UUID] = None
    target_type: Optional[str] = None
    target_id: Optional[str] = None
    reason: Optional[str] = None
    details: Dict[str, Any] = Field(default_factory=dict)
    ip_address: Optional[str] = None


class AuditPage(BaseModel):
    items: List[AuditEntryRead]
    total: int


class ChainVerification(BaseModel):
    intact: bool
    checked: int
    broken_at_id: Optional[int] = None


# ── Diagnóstico (sólo metadatos, P18) ──────────────────────────────────────

class DiagnosticUser(BaseModel):
    full_name: str
    email: str
    role: Optional[str] = None
    is_active: bool
    last_login_at: Optional[datetime] = None


class DiagnosticWarehouse(BaseModel):
    name: str
    is_active: bool
    is_default: bool


class TenantDiagnostics(BaseModel):
    catalog_enabled: Optional[bool] = Field(None, description="Vitrina web encendida; null si nunca la configuró")
    warehouses: List[DiagnosticWarehouse]
    users: List[DiagnosticUser]


# ── Exportaciones y aprobaciones ───────────────────────────────────────────

class ExportJobRead(BaseModel):
    id: uuid.UUID
    tenant_id: uuid.UUID
    status: Literal["PENDING", "SENT", "FAILED"]
    error: Optional[str] = None
    size_bytes: Optional[int] = None
    requested_by_name: Optional[str] = None
    created_at: datetime
    finished_at: Optional[datetime] = None


class ApprovalRead(BaseModel):
    id: uuid.UUID
    kind: str
    tenant_id: uuid.UUID
    tenant_name: str
    requested_by: uuid.UUID
    requested_by_name: Optional[str] = None
    reason: str
    status: Literal["PENDING", "APPROVED", "CANCELLED"]
    decided_by_name: Optional[str] = None
    decision_reason: Optional[str] = None
    decided_at: Optional[datetime] = None
    expires_at: datetime
    created_at: datetime
    expired: bool = False


class SupportState(BaseModel):
    """Lo que está en curso con este comercio (la ficha lo muestra arriba de las acciones)."""
    access_granted_until: Optional[datetime] = Field(None, description="El dueño concedió acceso de soporte hasta…")
    assisted_code_until: Optional[datetime] = Field(None, description="Código de recuperación asistida enviado y sin usar")
    pending_deletion: Optional[ApprovalRead] = None
    last_export: Optional[ExportJobRead] = None


class TenantDetail(TenantSummary):
    suspension_reason: Optional[str] = Field(None, description="Motivo de la suspensión por abuso vigente")
    diagnostics: TenantDiagnostics
    support: SupportState
    activity: List[AuditEntryRead]


# ── Acciones de soporte (todas con motivo, P8) ─────────────────────────────

class IdentityChecks(BaseModel):
    """Lo que el operador confirmó con el dueño (P21). Todo debe ir en `true`."""
    store_name: bool = Field(..., description="Dijo el nombre de la tienda")
    owner_email: bool = Field(..., description="Dijo el correo con el que entra")
    signup_date: bool = Field(..., description="Dijo cuándo se registró, aproximadamente")
    employees: bool = Field(..., description="Dijo quiénes trabajan en la tienda")


class AssistedRecoveryRequest(_WithReason):
    google_order_id: Optional[str] = Field(
        None,
        max_length=40,
        description="Número de orden de Google Play (GPA.…). Obligatorio si la suscripción viene de Google Play",
    )
    checks: IdentityChecks


class AssistedRecoveryResponse(BaseModel):
    sent_to: str = Field(..., description="Correo del dueño enmascarado: el operador no ve el código")
    expires_at: datetime


class GiftDaysRequest(_WithReason):
    days: int = Field(..., ge=1, le=90, description="Días que se suman a la vigencia")


class SuspendRequest(_WithReason):
    pass


class LiftSuspensionRequest(_WithReason):
    pass


class ExportRequest(_WithReason):
    pass


class DeletionRequest(_WithReason):
    confirm_slug: str = Field(..., max_length=100, description="Se escribe el slug de la tienda para confirmar")


class ApprovalDecisionRequest(_WithReason):
    pass


class OwnerPreviewRequest(BaseModel):
    """"Así lo verá la tienda": el mismo texto que le llegará al dueño, sin cambiar nada."""
    action: Literal[
        "ASSISTED_RECOVERY_SENT", "DAYS_GIFTED", "ABUSE_SUSPENDED", "ABUSE_LIFTED",
        "DATA_EXPORT_REQUESTED", "TENANT_DELETION_REQUESTED",
    ]
    days: Optional[int] = Field(None, ge=1, le=90)
    reason: Optional[str] = Field(None, max_length=500)


class OwnerPreview(BaseModel):
    summary: str
    reason: Optional[str] = None
    by: str


# ── Feed del día ───────────────────────────────────────────────────────────

AttentionKind = Literal[
    "DELETION_PENDING", "EXPORT_IN_PROGRESS", "EXPORT_FAILED",
    "SUPPORT_ACCESS_ACTIVE", "ASSISTED_CODE_UNUSED", "ABUSE_SUSPENSION",
]


class AttentionItem(BaseModel):
    kind: AttentionKind
    tenant_id: uuid.UUID
    tenant_name: str
    since: datetime
    until: Optional[datetime] = None
    summary: str
    ref_id: Optional[str] = None
    awaiting_you: bool = Field(
        False, description="Eliminación pedida por otro operador: te toca aprobarla o cancelarla",
    )


class FeedEvent(BaseModel):
    kind: Literal["AUDIT", "SIGNUP"]
    occurred_at: datetime
    action: Optional[str] = None
    tenant_id: Optional[uuid.UUID] = None
    tenant_name: Optional[str] = None
    operator_name: Optional[str] = None
    summary: str
    reason: Optional[str] = None


class Feed(BaseModel):
    attention: List[AttentionItem]
    events: List[FeedEvent]
    since: datetime
    until: datetime


# ── Métricas ───────────────────────────────────────────────────────────────

class PlatformMetrics(BaseModel):
    """Columna lateral del feed. El ingreso sólo existe cuando Google Play esté conectado (P13/P19)."""
    tenants_total: int
    tenants_by_status: Dict[TenantStatus, int]
    tenants_by_plan: Dict[TenantPlan, int]
    signups_last_30_days: int
    abuse_suspended: int
    revenue_connected: bool
    monthly_revenue_mxn: Optional[Decimal] = None
