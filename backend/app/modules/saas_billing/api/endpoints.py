# Importación de módulos de tipado y UUID
from typing import List, Optional
import uuid

# Importación de FastAPI y componentes de ruteo
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de dependencias de seguridad y base de datos
from app.core.database.session import get_db
from app.core.security.deps import get_current_user
from app.modules.auth_tenancy.domain.user import User
from app.modules.saas_billing.domain.subscription_invoice import SubscriptionInvoiceStatus
from app.modules.saas_billing.schemas.saas_schemas import (
    GeneratePaymentMethodRequest,
    InvoiceItemResponse,
    InvoiceListResponse,
    OxxoWebhookPayload,
    PaymentMethodDetailsResponse,
    PlanResponse,
    SpeiWebhookPayload,
    SubscriptionChangePlanRequest,
    SubscriptionChangePlanResponse,
    SubscriptionResponse,
    WebhookConfirmationResponse,
)
from app.modules.saas_billing.services.subscription_service import SubscriptionService

# Definición del enrutador principal para suscripciones y facturación SaaS
router = APIRouter(tags=["SaaS & Facturación"])


# -----------------------------------------------------------------------------
# 1. PLANES SAAS Y SUSCRIPCIONES
# -----------------------------------------------------------------------------

@router.get(
    "/saas/plans",
    response_model=List[PlanResponse],
    status_code=status.HTTP_200_OK,
    summary="Listar planes SaaS disponibles",
    description="Retorna el catálogo oficial de planes con precios en Pesos Mexicanos (MXN) y límites.",
)
async def list_saas_plans(
    db: AsyncSession = Depends(get_db),
) -> List[PlanResponse]:
    """Consulta los planes comerciales disponibles para contratación."""
    service = SubscriptionService(db)
    return await service.get_plans()


@router.get(
    "/subscription",
    response_model=SubscriptionResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener información de la suscripción actual",
    description="Retorna los detalles de la suscripción activa del tenant en sesión con sus estadísticas de uso.",
)
async def get_subscription_info(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> SubscriptionResponse:
    """Devuelve la información de suscripción del comercio autenticado."""
    service = SubscriptionService(db)
    return await service.get_subscription(current_user.tenant_id)


@router.post(
    "/subscription/change-plan",
    response_model=SubscriptionChangePlanResponse,
    status_code=status.HTTP_200_OK,
    summary="Solicitar cambio de plan de suscripción",
    description="Permite solicitar un upgrade o downgrade validando que las métricas de uso no superen los límites.",
)
async def change_subscription_plan(
    request: SubscriptionChangePlanRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> SubscriptionChangePlanResponse:
    """Modifica el nivel de plan de la cuenta del comercio."""
    service = SubscriptionService(db)
    return await service.change_plan(current_user.tenant_id, request)


# -----------------------------------------------------------------------------
# 2. HISTORIAL DE FACTURACIÓN Y GENERACIÓN DE MÉTODOS DE PAGO
# -----------------------------------------------------------------------------

@router.get(
    "/billing/invoices",
    response_model=InvoiceListResponse,
    status_code=status.HTTP_200_OK,
    summary="Listar facturas de suscripción",
    description="Retorna el historial paginado de facturas mensuales del comercio.",
)
async def list_billing_invoices(
    status_filter: Optional[SubscriptionInvoiceStatus] = Query(None, alias="status", description="Filtrar por estado"),
    year: Optional[int] = Query(None, ge=2025, description="Filtrar por año"),
    month: Optional[int] = Query(None, ge=1, le=12, description="Filtrar por mes"),
    page: int = Query(1, ge=1, description="Número de página"),
    page_size: int = Query(20, ge=1, le=100, description="Registros por página"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> InvoiceListResponse:
    """Recupera el historial de recibos y facturas de suscripción emitidas."""
    service = SubscriptionService(db)
    return await service.list_invoices(
        tenant_id=current_user.tenant_id,
        status_filter=status_filter,
        year=year,
        month=month,
        page=page,
        page_size=page_size,
    )


@router.get(
    "/billing/invoices/{id}",
    response_model=InvoiceItemResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener detalle de factura específica",
)
async def get_billing_invoice_detail(
    id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> InvoiceItemResponse:
    """Devuelve la información detallada de una factura de suscripción."""
    service = SubscriptionService(db)
    return await service.get_invoice_detail(id, current_user.tenant_id)


@router.post(
    "/billing/invoices/{id}/payment-methods",
    response_model=PaymentMethodDetailsResponse,
    status_code=status.HTTP_200_OK,
    summary="Generar método de pago para factura pendiente",
    description="Genera la CLABE interbancaria (SPEI vía STP) o referencia de 14 dígitos (OXXO Pay) para liquidar.",
)
async def generate_invoice_payment_method(
    id: uuid.UUID,
    request: GeneratePaymentMethodRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> PaymentMethodDetailsResponse:
    """Genera las instrucciones de pago en moneda nacional para la factura indicada."""
    service = SubscriptionService(db)
    return await service.generate_payment_method(id, current_user.tenant_id, request)


# -----------------------------------------------------------------------------
# 3. WEBHOOKS DE PASARELAS DE PAGO (SPEI STP / OXXO PAY)
# -----------------------------------------------------------------------------

@router.post(
    "/webhooks/spei/payment-confirmation",
    response_model=WebhookConfirmationResponse,
    status_code=status.HTTP_200_OK,
    summary="Webhook de confirmación de pago SPEI",
    description="Endpoint seguro para recibir notificaciones automáticas de transferencias bancarias SPEI vía STP.",
)
async def webhook_spei_payment_confirmation(
    payload: SpeiWebhookPayload,
    db: AsyncSession = Depends(get_db),
) -> WebhookConfirmationResponse:
    """Procesa la confirmación de pago interbancario SPEI y reactiva la cuenta si aplica."""
    service = SubscriptionService(db)
    return await service.process_spei_webhook(payload)


@router.post(
    "/webhooks/oxxo/payment-confirmation",
    response_model=WebhookConfirmationResponse,
    status_code=status.HTTP_200_OK,
    summary="Webhook de confirmación de pago OXXO",
    description="Endpoint seguro para recibir notificaciones de pagos liquidados en tiendas de conveniencia OXXO.",
)
async def webhook_oxxo_payment_confirmation(
    payload: OxxoWebhookPayload,
    db: AsyncSession = Depends(get_db),
) -> WebhookConfirmationResponse:
    """Procesa la confirmación de abono en tiendas OXXO y reactiva la cuenta si aplica."""
    service = SubscriptionService(db)
    return await service.process_oxxo_webhook(payload)
