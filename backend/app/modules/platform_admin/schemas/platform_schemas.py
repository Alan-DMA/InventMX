"""Esquemas del panel de plataforma (Fase 1)."""
import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.modules.auth_tenancy.domain.tenant import TenantPlan, TenantStatus
from app.modules.saas_billing.domain.subscription_invoice import (
    SaasPaymentMethod,
    SubscriptionInvoiceStatus,
)

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
    created_at: datetime
    owner_name: Optional[str] = None
    owner_email: Optional[str] = None
    users_count: int
    users_limit: int
    last_activity_at: Optional[datetime] = None
    open_invoices: int


class TenantPage(BaseModel):
    items: List[TenantSummary]
    total: int


class InvoiceRead(BaseModel):
    id: uuid.UUID
    tenant_id: uuid.UUID
    tenant_name: Optional[str] = None
    plan: TenantPlan
    amount_mxn: Decimal
    payment_method: SaasPaymentMethod
    status: SubscriptionInvoiceStatus
    period_start: date
    period_end: date
    payment_reference: Optional[str] = None
    paid_at: Optional[datetime] = None
    created_at: datetime


class InvoicePage(BaseModel):
    items: List[InvoiceRead]
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


class TenantDetail(TenantSummary):
    invoices: List[InvoiceRead]
    activity: List[AuditEntryRead]


# ── Acciones de suscripción (todas con motivo) ─────────────────────────────

class ConfirmPaymentRequest(_WithReason):
    invoice_id: uuid.UUID
    method: Literal[SaasPaymentMethod.CASH, SaasPaymentMethod.MANUAL_SPEI]
    reference: Optional[str] = Field(None, max_length=100, description="Clave de rastreo o folio del recibo")


class ChangeStatusRequest(_WithReason):
    status: TenantStatus


class ChangePlanRequest(_WithReason):
    plan: TenantPlan


class CourtesyRequest(_WithReason):
    pass


# ── Métricas ───────────────────────────────────────────────────────────────

class PlatformMetrics(BaseModel):
    """Constitución §5.3. MRR = mensualidad de los comercios que no están en bloqueo total."""
    mrr_mxn: Decimal
    tenants_total: int
    tenants_by_status: Dict[TenantStatus, int]
    tenants_by_plan: Dict[TenantPlan, int]
    signups_last_30_days: int
    open_invoices: int
    open_invoices_amount_mxn: Decimal
