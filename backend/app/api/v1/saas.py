from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, or_
from sqlalchemy.orm import selectinload
from decimal import Decimal
from uuid import UUID
from typing import List, Optional
from datetime import datetime, timedelta
import calendar

from app.core.database import get_db
from app.core.saas_config import (
    NEXUS_SPEI_CLABE,
    NEXUS_SPEI_BANK,
    NEXUS_SPEI_HOLDER,
    SOFT_LOCK_DAYS,
    HARD_LOCK_FROM_DAY,
)
from app.api.saas_deps import (
    get_current_user_allow_locked,
    require_saas_manage,
    get_user_tenant,
    user_permissions,
    is_founder,
)
from app.models.models import (
    User,
    Tenant,
    Plan,
    Role,
    SubscriptionInvoice,
    SubscriptionPaymentValidation,
)
from app.schemas.saas import (
    PlanOut,
    InvoiceOut,
    PaymentValidationIn,
    PaymentValidationOut,
    PaymentInstructionsOut,
    TenantBriefOut,
    SubscriptionOut,
    ChangePlanIn,
    UserBriefOut,
    MeOut,
    FounderMetricsOut,
    TenantAdminOut,
    ValidationAdminOut,
    ValidationDecisionIn,
    ValidationRejectIn,
    TenantStatusIn,
    ExtendDueIn,
    ValidationDecisionOut,
    LifecycleRunOut,
)

# ---------------------------------------------------------------------------
# Módulo SaaS — suscripción del comerciante y panel de fundadores (Tarea 14.2)
#
# Se monta en /api/v1/saas sobre el backend legacy (models.py). Sin proveedor
# de pagos: el comercio transfiere a la CLABE fija de Nexus con concepto =
# `tenant.code`, reporta el pago y un fundador lo valida (Constitución Art. V
# §5.2 "SPEI Manual (Captura)"). La máquina de estados (Art. VI §6.3) se
# evalúa de forma perezosa aquí porque el cron de 14.1.3 no existe.
# ---------------------------------------------------------------------------

router = APIRouter()

INVOICE_PENDING = "PENDIENTE"
INVOICE_PAID = "PAGADA"
VALIDATION_PENDING = "PENDIENTE"
VALIDATION_APPROVED = "APROBADA"
VALIDATION_REJECTED = "RECHAZADA"
OWNER_ROLE_NAME = "TENANT_OWNER"

_STATUS_RANK = {"ACTIVE": 0, "SOFT_LOCK": 1, "HARD_LOCK": 2}


# --- Helpers de dominio ------------------------------------------------------

def _now() -> datetime:
    # Las tablas legacy guardan DateTime naive en UTC (datetime.utcnow en models.py)
    return datetime.utcnow()


def _add_months(dt: datetime, months: int) -> datetime:
    """Suma meses calendario conservando el día (recortado al último del mes):
    una mensualidad vence cada mes en la misma fecha, no cada 30 días —
    así nunca hay dos facturas etiquetadas con el mismo mes."""
    month_index = dt.month - 1 + months
    year = dt.year + month_index // 12
    month = month_index % 12 + 1
    day = min(dt.day, calendar.monthrange(year, month)[1])
    return dt.replace(year=year, month=month, day=day)


def _days_overdue(invoice: Optional[SubscriptionInvoice], now: datetime) -> int:
    if invoice is None or invoice.status != INVOICE_PENDING:
        return 0
    delta = now.date() - invoice.due_date.date()
    return max(delta.days, 0)


def _expected_status(days_overdue: int) -> str:
    if days_overdue >= HARD_LOCK_FROM_DAY:
        return "HARD_LOCK"
    if days_overdue >= 1:
        return "SOFT_LOCK"
    return "ACTIVE"


def _escalate_if_needed(tenant: Tenant, invoice: Optional[SubscriptionInvoice], now: datetime) -> bool:
    """Sube el estado del tenant según la morosidad. Nunca lo baja: bajar es
    consecuencia de un pago aprobado o de una acción explícita de fundador."""
    expected = _expected_status(_days_overdue(invoice, now))
    current = tenant.subscription_status or "ACTIVE"
    if _STATUS_RANK.get(expected, 0) > _STATUS_RANK.get(current, 0):
        tenant.subscription_status = expected
        return True
    return False


async def _get_plan(db: AsyncSession, plan_id: Optional[UUID]) -> Optional[Plan]:
    if plan_id is None:
        return None
    return (await db.execute(select(Plan).where(Plan.id == plan_id))).scalars().first()


async def _pending_invoice(db: AsyncSession, tenant_id: UUID) -> Optional[SubscriptionInvoice]:
    result = await db.execute(
        select(SubscriptionInvoice)
        .where(
            SubscriptionInvoice.tenant_id == tenant_id,
            SubscriptionInvoice.status == INVOICE_PENDING,
        )
        .order_by(SubscriptionInvoice.due_date.asc())
    )
    return result.scalars().first()


async def _ensure_pending_invoice(
    db: AsyncSession, tenant: Tenant, plan: Optional[Plan], now: datetime
) -> Optional[SubscriptionInvoice]:
    """Facturación perezosa: si el tenant tiene plan y ninguna factura pendiente,
    se genera la del siguiente periodo (un mes después de la última pagada, o
    un mes después del alta si nunca ha pagado)."""
    invoice = await _pending_invoice(db, tenant.id)
    if invoice is not None or plan is None:
        return invoice

    last_paid = (
        await db.execute(
            select(SubscriptionInvoice)
            .where(
                SubscriptionInvoice.tenant_id == tenant.id,
                SubscriptionInvoice.status == INVOICE_PAID,
            )
            .order_by(SubscriptionInvoice.due_date.desc())
        )
    ).scalars().first()

    base = last_paid.due_date if last_paid else (tenant.created_at or now)
    due = _add_months(base, 1)

    invoice = SubscriptionInvoice(
        tenant_id=tenant.id,
        plan_id=plan.id,
        amount=plan.price,
        due_date=due,
        status=INVOICE_PENDING,
    )
    db.add(invoice)
    await db.commit()
    await db.refresh(invoice)
    return invoice


async def _pending_validation(
    db: AsyncSession, invoice_id: UUID
) -> Optional[SubscriptionPaymentValidation]:
    result = await db.execute(
        select(SubscriptionPaymentValidation).where(
            SubscriptionPaymentValidation.subscription_invoice_id == invoice_id,
            SubscriptionPaymentValidation.status == VALIDATION_PENDING,
        )
    )
    return result.scalars().first()


def _invoice_out(invoice: SubscriptionInvoice, plan_name: Optional[str]) -> InvoiceOut:
    return InvoiceOut(
        id=invoice.id,
        tenant_id=invoice.tenant_id,
        plan_id=invoice.plan_id,
        plan_name=plan_name,
        amount=invoice.amount,
        due_date=invoice.due_date,
        status=invoice.status,
        created_at=invoice.created_at,
    )


def _tenant_brief(tenant: Tenant) -> TenantBriefOut:
    return TenantBriefOut(
        id=tenant.id,
        code=tenant.code,
        name=tenant.name,
        plan_id=tenant.plan_id,
        subscription_status=tenant.subscription_status or "ACTIVE",
    )


async def _plan_names(db: AsyncSession) -> dict:
    plans = (await db.execute(select(Plan))).scalars().all()
    return {p.id: p for p in plans}


# --- Comerciante -------------------------------------------------------------

@router.get("/me", response_model=MeOut)
async def read_me(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user_allow_locked),
):
    """Perfil de sesión: permisos, si es fundador y estado del comercio.
    Existe porque `LoginResponse` no devuelve permisos (blocker registrado)."""
    tenant = await get_user_tenant(db, current_user)
    return MeOut(
        user=UserBriefOut(
            id=current_user.id,
            email=current_user.email,
            username=current_user.username,
            role_name=current_user.role.name if current_user.role else None,
        ),
        permissions=user_permissions(current_user),
        is_founder=is_founder(current_user),
        tenant=_tenant_brief(tenant),
    )


@router.get("/plans", response_model=List[PlanOut])
async def list_plans(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user_allow_locked),
):
    plans = (await db.execute(select(Plan).order_by(Plan.price.asc()))).scalars().all()
    return plans


@router.get("/subscription", response_model=SubscriptionOut)
async def read_subscription(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user_allow_locked),
):
    """Plan, estado, factura pendiente del periodo e instrucciones de pago."""
    now = _now()
    tenant = await get_user_tenant(db, current_user)
    plan = await _get_plan(db, tenant.plan_id)
    invoice = await _ensure_pending_invoice(db, tenant, plan, now)

    if _escalate_if_needed(tenant, invoice, now):
        await db.commit()
        await db.refresh(tenant)

    validation = await _pending_validation(db, invoice.id) if invoice else None
    days_overdue = _days_overdue(invoice, now)

    instructions = None
    if invoice is not None:
        instructions = PaymentInstructionsOut(
            clabe=NEXUS_SPEI_CLABE,
            bank=NEXUS_SPEI_BANK,
            holder=NEXUS_SPEI_HOLDER,
            concept=tenant.code or str(tenant.id)[:8].upper(),
            amount=invoice.amount,
        )

    return SubscriptionOut(
        tenant=_tenant_brief(tenant),
        plan=plan,
        status=tenant.subscription_status or "ACTIVE",
        pending_invoice=_invoice_out(invoice, plan.name if plan else None) if invoice else None,
        pending_validation=validation,
        days_overdue=days_overdue,
        soft_lock_at=(invoice.due_date + timedelta(days=1)) if invoice else None,
        hard_lock_at=(invoice.due_date + timedelta(days=HARD_LOCK_FROM_DAY)) if invoice else None,
        payment_instructions=instructions,
        oxxo=None,  # Sin proveedor OXXO Pay en el MVP — el frontend lo muestra como "próximamente"
    )


@router.get("/invoices", response_model=List[InvoiceOut])
async def list_invoices(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user_allow_locked),
):
    plans = await _plan_names(db)
    result = await db.execute(
        select(SubscriptionInvoice)
        .where(SubscriptionInvoice.tenant_id == current_user.tenant_id)
        .order_by(SubscriptionInvoice.due_date.desc())
    )
    return [
        _invoice_out(inv, plans[inv.plan_id].name if inv.plan_id in plans else None)
        for inv in result.scalars().all()
    ]


@router.post("/subscription/change-plan", response_model=SubscriptionOut)
async def change_plan(
    payload: ChangePlanIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user_allow_locked),
):
    """Cambia el plan del comercio. Si la factura pendiente aún no tiene un
    aviso de pago en revisión, se recalcula a la tarifa del nuevo plan."""
    if current_user.role is None or current_user.role.name != OWNER_ROLE_NAME:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo el propietario del comercio puede cambiar el plan.",
        )
    plan = await _get_plan(db, payload.plan_id)
    if plan is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Plan no encontrado.")

    tenant = await get_user_tenant(db, current_user)
    tenant.plan_id = plan.id

    invoice = await _pending_invoice(db, tenant.id)
    if invoice is not None:
        in_review = await _pending_validation(db, invoice.id)
        if in_review is not None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Tienes un aviso de pago en revisión. Espera la validación antes de cambiar de plan.",
            )
        invoice.plan_id = plan.id
        invoice.amount = plan.price
    await db.commit()
    return await read_subscription(db=db, current_user=current_user)


@router.post("/payment-validations", response_model=PaymentValidationOut, status_code=status.HTTP_201_CREATED)
async def report_payment(
    payload: PaymentValidationIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user_allow_locked),
):
    """"Ya pagué": registra el aviso de pago para que un fundador lo valide."""
    invoice = (
        await db.execute(
            select(SubscriptionInvoice).where(
                SubscriptionInvoice.id == payload.invoice_id,
                SubscriptionInvoice.tenant_id == current_user.tenant_id,
            )
        )
    ).scalars().first()
    if invoice is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Factura no encontrada.")
    if invoice.status == INVOICE_PAID:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Esta factura ya está pagada.",
        )
    if await _pending_validation(db, invoice.id) is not None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Ya recibimos un aviso de pago para esta factura; está en revisión.",
        )

    validation = SubscriptionPaymentValidation(
        tenant_id=current_user.tenant_id,
        subscription_invoice_id=invoice.id,
        payment_method=payload.payment_method,
        reference_number=payload.reference_number.strip(),
        receipt_file_url=payload.receipt_file_url,
        status=VALIDATION_PENDING,
    )
    db.add(validation)
    await db.commit()
    await db.refresh(validation)
    return validation


@router.get("/payment-validations", response_model=List[PaymentValidationOut])
async def list_my_validations(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user_allow_locked),
):
    result = await db.execute(
        select(SubscriptionPaymentValidation)
        .where(SubscriptionPaymentValidation.tenant_id == current_user.tenant_id)
        .order_by(SubscriptionPaymentValidation.created_at.desc())
    )
    return result.scalars().all()


# --- Fundadores --------------------------------------------------------------

async def _owner_emails(db: AsyncSession) -> dict:
    result = await db.execute(
        select(User.tenant_id, User.email)
        .join(Role, Role.id == User.role_id)
        .where(Role.name == OWNER_ROLE_NAME)
    )
    emails = {}
    for tenant_id, email in result.all():
        emails.setdefault(tenant_id, email)
    return emails


@router.get("/admin/metrics", response_model=FounderMetricsOut)
async def founder_metrics(
    db: AsyncSession = Depends(get_db),
    founder: User = Depends(require_saas_manage),
):
    """MRR = suma de la tarifa del plan de los comercios ACTIVE."""
    now = _now()
    plans = await _plan_names(db)
    tenants = (await db.execute(select(Tenant))).scalars().all()

    mrr = Decimal("0")
    counts = {"ACTIVE": 0, "SOFT_LOCK": 0, "HARD_LOCK": 0}
    new_30d = 0
    for t in tenants:
        st = t.subscription_status or "ACTIVE"
        counts[st] = counts.get(st, 0) + 1
        if st == "ACTIVE" and t.plan_id in plans:
            mrr += plans[t.plan_id].price
        if t.created_at and t.created_at >= now - timedelta(days=30):
            new_30d += 1

    pending = (
        await db.execute(
            select(func.count(SubscriptionPaymentValidation.id)).where(
                SubscriptionPaymentValidation.status == VALIDATION_PENDING
            )
        )
    ).scalar_one()

    total = len(tenants)
    return FounderMetricsOut(
        mrr_mxn=mrr,
        tenants_total=total,
        tenants_active=counts.get("ACTIVE", 0),
        tenants_soft_lock=counts.get("SOFT_LOCK", 0),
        tenants_hard_lock=counts.get("HARD_LOCK", 0),
        new_tenants_30d=new_30d,
        pending_validations=int(pending),
        retention_rate=(counts.get("ACTIVE", 0) / total) if total else 0.0,
    )


@router.get("/admin/tenants", response_model=List[TenantAdminOut])
async def founder_tenants(
    status_filter: Optional[str] = Query(default=None, alias="status"),
    plan_id: Optional[UUID] = Query(default=None),
    q: Optional[str] = Query(default=None, max_length=100),
    db: AsyncSession = Depends(get_db),
    founder: User = Depends(require_saas_manage),
):
    now = _now()
    plans = await _plan_names(db)
    owners = await _owner_emails(db)

    stmt = select(Tenant).order_by(Tenant.created_at.desc())
    if status_filter:
        stmt = stmt.where(Tenant.subscription_status == status_filter)
    if plan_id:
        stmt = stmt.where(Tenant.plan_id == plan_id)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(or_(Tenant.name.ilike(like), Tenant.code.ilike(like)))
    tenants = (await db.execute(stmt)).scalars().all()

    out: List[TenantAdminOut] = []
    for t in tenants:
        invoice = await _pending_invoice(db, t.id)
        last_validation = (
            await db.execute(
                select(SubscriptionPaymentValidation)
                .where(SubscriptionPaymentValidation.tenant_id == t.id)
                .order_by(SubscriptionPaymentValidation.created_at.desc())
            )
        ).scalars().first()
        plan = plans.get(t.plan_id)
        out.append(
            TenantAdminOut(
                id=t.id,
                code=t.code,
                name=t.name,
                owner_email=owners.get(t.id),
                plan=plan,
                subscription_status=t.subscription_status or "ACTIVE",
                created_at=t.created_at,
                pending_invoice=_invoice_out(invoice, plan.name if plan else None) if invoice else None,
                days_overdue=_days_overdue(invoice, now),
                last_validation=last_validation,
            )
        )
    return out


@router.get("/admin/payment-validations", response_model=List[ValidationAdminOut])
async def founder_validations(
    status_filter: Optional[str] = Query(default=VALIDATION_PENDING, alias="status"),
    db: AsyncSession = Depends(get_db),
    founder: User = Depends(require_saas_manage),
):
    """Bandeja de conciliación manual (Constitución Art. V §5.3)."""
    stmt = (
        select(SubscriptionPaymentValidation, Tenant, SubscriptionInvoice)
        .join(Tenant, Tenant.id == SubscriptionPaymentValidation.tenant_id)
        .join(SubscriptionInvoice, SubscriptionInvoice.id == SubscriptionPaymentValidation.subscription_invoice_id)
        .order_by(SubscriptionPaymentValidation.created_at.asc())
    )
    if status_filter:
        stmt = stmt.where(SubscriptionPaymentValidation.status == status_filter)
    rows = (await db.execute(stmt)).all()
    return [
        ValidationAdminOut(
            **PaymentValidationOut.model_validate(v).model_dump(),
            tenant_code=t.code,
            tenant_name=t.name,
            invoice_amount=inv.amount,
            invoice_due_date=inv.due_date,
        )
        for v, t, inv in rows
    ]


async def _load_validation_for_decision(db: AsyncSession, validation_id: UUID):
    validation = (
        await db.execute(
            select(SubscriptionPaymentValidation).where(SubscriptionPaymentValidation.id == validation_id)
        )
    ).scalars().first()
    if validation is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Aviso de pago no encontrado.")
    if validation.status != VALIDATION_PENDING:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Este aviso ya fue resuelto ({validation.status}).",
        )
    invoice = (
        await db.execute(
            select(SubscriptionInvoice).where(SubscriptionInvoice.id == validation.subscription_invoice_id)
        )
    ).scalars().first()
    tenant = (await db.execute(select(Tenant).where(Tenant.id == validation.tenant_id))).scalars().first()
    if invoice is None or tenant is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Factura o comercio no encontrado.")
    return validation, invoice, tenant


@router.post("/admin/payment-validations/{validation_id}/approve", response_model=ValidationDecisionOut)
async def approve_validation(
    validation_id: UUID,
    payload: ValidationDecisionIn = ValidationDecisionIn(),
    db: AsyncSession = Depends(get_db),
    founder: User = Depends(require_saas_manage),
):
    """Aprobar = factura PAGADA + comercio ACTIVE, en una sola transacción."""
    validation, invoice, tenant = await _load_validation_for_decision(db, validation_id)
    now = _now()

    validation.status = VALIDATION_APPROVED
    validation.validated_by = founder.id
    validation.validation_notes = payload.validation_notes
    validation.updated_at = now
    invoice.status = INVOICE_PAID
    tenant.subscription_status = "ACTIVE"
    await db.commit()
    await db.refresh(validation)
    await db.refresh(invoice)
    await db.refresh(tenant)

    plan = await _get_plan(db, invoice.plan_id)
    return ValidationDecisionOut(
        validation=validation,
        invoice=_invoice_out(invoice, plan.name if plan else None),
        tenant=_tenant_brief(tenant),
    )


@router.post("/admin/payment-validations/{validation_id}/reject", response_model=ValidationDecisionOut)
async def reject_validation(
    validation_id: UUID,
    payload: ValidationRejectIn,
    db: AsyncSession = Depends(get_db),
    founder: User = Depends(require_saas_manage),
):
    """Rechazar exige motivo: el comercio lo lee para corregir su pago."""
    validation, invoice, tenant = await _load_validation_for_decision(db, validation_id)
    validation.status = VALIDATION_REJECTED
    validation.validated_by = founder.id
    validation.validation_notes = payload.validation_notes.strip()
    validation.updated_at = _now()
    await db.commit()
    await db.refresh(validation)

    plan = await _get_plan(db, invoice.plan_id)
    return ValidationDecisionOut(
        validation=validation,
        invoice=_invoice_out(invoice, plan.name if plan else None),
        tenant=_tenant_brief(tenant),
    )


@router.post("/admin/tenants/{tenant_id}/status", response_model=TenantAdminOut)
async def set_tenant_status(
    tenant_id: UUID,
    payload: TenantStatusIn,
    db: AsyncSession = Depends(get_db),
    founder: User = Depends(require_saas_manage),
):
    """Reactivación rápida o suspensión manual. Al reactivar un comercio con
    factura vencida se extiende el vencimiento 7 días: de lo contrario la
    evaluación perezosa lo volvería a bloquear en la siguiente lectura."""
    tenant = (await db.execute(select(Tenant).where(Tenant.id == tenant_id))).scalars().first()
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Comercio no encontrado.")
    now = _now()
    invoice = await _pending_invoice(db, tenant.id)

    tenant.subscription_status = payload.status
    if payload.status == "ACTIVE" and invoice is not None and _days_overdue(invoice, now) > 0:
        invoice.due_date = now + timedelta(days=7)
    await db.commit()
    await db.refresh(tenant)
    if invoice is not None:
        await db.refresh(invoice)

    plan = await _get_plan(db, tenant.plan_id)
    owners = await _owner_emails(db)
    return TenantAdminOut(
        id=tenant.id,
        code=tenant.code,
        name=tenant.name,
        owner_email=owners.get(tenant.id),
        plan=plan,
        subscription_status=tenant.subscription_status,
        created_at=tenant.created_at,
        pending_invoice=_invoice_out(invoice, plan.name if plan else None) if invoice else None,
        days_overdue=_days_overdue(invoice, now),
        last_validation=None,
    )


@router.post("/admin/tenants/{tenant_id}/extend-due", response_model=InvoiceOut)
async def extend_due_date(
    tenant_id: UUID,
    payload: ExtendDueIn,
    db: AsyncSession = Depends(get_db),
    founder: User = Depends(require_saas_manage),
):
    """Extiende el plazo de la factura pendiente (sustituye a "extender trial":
    el modelo legacy no tiene periodo de prueba)."""
    invoice = await _pending_invoice(db, tenant_id)
    if invoice is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="El comercio no tiene factura pendiente que extender.",
        )
    now = _now()
    base = invoice.due_date if invoice.due_date > now else now
    invoice.due_date = base + timedelta(days=payload.days)

    tenant = (await db.execute(select(Tenant).where(Tenant.id == tenant_id))).scalars().first()
    if tenant is not None and _days_overdue(invoice, now) == 0 and tenant.subscription_status != "ACTIVE":
        tenant.subscription_status = "ACTIVE"
    await db.commit()
    await db.refresh(invoice)
    plan = await _get_plan(db, invoice.plan_id)
    return _invoice_out(invoice, plan.name if plan else None)


@router.post("/admin/lifecycle/run", response_model=LifecycleRunOut)
async def run_lifecycle(
    db: AsyncSession = Depends(get_db),
    founder: User = Depends(require_saas_manage),
):
    """Lo que haría el cron diario de 14.1.3: evalúa vencimientos y escala
    ACTIVE → SOFT_LOCK → HARD_LOCK. Nunca reactiva."""
    now = _now()
    tenants = (await db.execute(select(Tenant))).scalars().all()
    to_soft, to_hard = [], []
    for t in tenants:
        invoice = await _pending_invoice(db, t.id)
        if _escalate_if_needed(t, invoice, now):
            (to_hard if t.subscription_status == "HARD_LOCK" else to_soft).append(t.id)
    await db.commit()
    return LifecycleRunOut(evaluated=len(tenants), to_soft_lock=to_soft, to_hard_lock=to_hard)
