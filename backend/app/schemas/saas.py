from pydantic import BaseModel, Field
from uuid import UUID
from decimal import Decimal
from typing import Optional, List, Literal
from datetime import datetime

# ---------------------------------------------------------------------------
# Esquemas del módulo SaaS (Tarea 14.2) — sobre las tablas legacy `plans`,
# `subscription_invoices` y `subscription_payment_validations`.
# Vocabulario de estados en español: es el que ya usan las tablas.
# ---------------------------------------------------------------------------

InvoiceStatus = Literal["PENDIENTE", "PAGADA", "CANCELADA"]
ValidationStatus = Literal["PENDIENTE", "APROBADA", "RECHAZADA"]
TenantStatus = Literal["ACTIVE", "SOFT_LOCK", "HARD_LOCK"]
PaymentMethod = Literal["SPEI", "OXXO", "EFECTIVO"]


# --- Planes ---
class PlanOut(BaseModel):
    id: UUID
    name: str
    price: Decimal
    max_users: int
    max_warehouses: int

    class Config:
        from_attributes = True


# --- Facturas ---
class InvoiceOut(BaseModel):
    id: UUID
    tenant_id: UUID
    plan_id: UUID
    plan_name: Optional[str] = None
    amount: Decimal
    due_date: datetime
    status: str
    created_at: Optional[datetime] = None


# --- Validaciones de pago manual ---
class PaymentValidationIn(BaseModel):
    invoice_id: UUID
    payment_method: PaymentMethod
    reference_number: str = Field(..., min_length=4, max_length=100, description="Folio/clave de rastreo SPEI, referencia OXXO o nota del efectivo")
    receipt_file_url: Optional[str] = Field(default=None, max_length=255)


class PaymentValidationOut(BaseModel):
    id: UUID
    tenant_id: UUID
    subscription_invoice_id: UUID
    payment_method: str
    reference_number: Optional[str] = None
    receipt_file_url: Optional[str] = None
    status: str
    validated_by: Optional[UUID] = None
    validation_notes: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True


# --- Suscripción del tenant ---
class PaymentInstructionsOut(BaseModel):
    clabe: str
    bank: str
    holder: str
    concept: str = Field(..., description="Concepto de la transferencia = código del comercio")
    amount: Decimal


class OxxoInstructionsOut(BaseModel):
    reference_number: str
    barcode: str
    expires_at: datetime


class TenantBriefOut(BaseModel):
    id: UUID
    code: Optional[str] = None
    name: str
    plan_id: Optional[UUID] = None
    subscription_status: str


class SubscriptionOut(BaseModel):
    tenant: TenantBriefOut
    plan: Optional[PlanOut] = None
    status: str
    pending_invoice: Optional[InvoiceOut] = None
    pending_validation: Optional[PaymentValidationOut] = None
    days_overdue: int = 0
    soft_lock_at: Optional[datetime] = None
    hard_lock_at: Optional[datetime] = None
    payment_instructions: Optional[PaymentInstructionsOut] = None
    oxxo: Optional[OxxoInstructionsOut] = None


class ChangePlanIn(BaseModel):
    plan_id: UUID


class UserBriefOut(BaseModel):
    id: UUID
    email: str
    username: str
    role_name: Optional[str] = None


class MeOut(BaseModel):
    user: UserBriefOut
    permissions: List[str]
    is_founder: bool
    tenant: TenantBriefOut


# --- Panel de fundadores ---
class FounderMetricsOut(BaseModel):
    mrr_mxn: Decimal
    tenants_total: int
    tenants_active: int
    tenants_soft_lock: int
    tenants_hard_lock: int
    new_tenants_30d: int
    pending_validations: int
    retention_rate: float = Field(..., description="tenants_active / tenants_total (0-1)")


class TenantAdminOut(BaseModel):
    id: UUID
    code: Optional[str] = None
    name: str
    owner_email: Optional[str] = None
    plan: Optional[PlanOut] = None
    subscription_status: str
    created_at: Optional[datetime] = None
    pending_invoice: Optional[InvoiceOut] = None
    days_overdue: int = 0
    last_validation: Optional[PaymentValidationOut] = None


class ValidationAdminOut(PaymentValidationOut):
    tenant_code: Optional[str] = None
    tenant_name: str
    invoice_amount: Decimal
    invoice_due_date: datetime


class ValidationDecisionIn(BaseModel):
    validation_notes: Optional[str] = Field(default=None, max_length=500)


class ValidationRejectIn(BaseModel):
    validation_notes: str = Field(..., min_length=3, max_length=500, description="Motivo del rechazo — obligatorio, el comercio lo lee")


class TenantStatusIn(BaseModel):
    status: TenantStatus


class ExtendDueIn(BaseModel):
    days: int = Field(..., ge=1, le=60)


class ValidationDecisionOut(BaseModel):
    validation: PaymentValidationOut
    invoice: InvoiceOut
    tenant: TenantBriefOut


class LifecycleRunOut(BaseModel):
    evaluated: int
    to_soft_lock: List[UUID]
    to_hard_lock: List[UUID]
