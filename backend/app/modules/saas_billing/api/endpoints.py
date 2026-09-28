# Importación de módulos de tipado y UUID
from typing import List, Optional
import uuid

# Importación de FastAPI y componentes de ruteo
from fastapi import APIRouter, Depends, Header, Query, Request, status
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de dependencias de seguridad y base de datos
from app.core.config.settings import settings
from app.core.database.session import get_db
from app.core.security.webhook_signature import SIGNATURE_HEADER, verify_webhook_signature
from app.core.security.deps import get_current_user, require_owner
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
from app.modules.platform_admin.services.tenant_activity import (
    SupportActivityItem,
    support_activity_for_tenant,
)

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


@router.get(
    "/subscription/activity",
    response_model=List[SupportActivityItem],
    summary="Lo que soporte Nexus hizo en tu suscripción",
)
async def get_support_activity(
    current_user: User = Depends(require_owner),
    db: AsyncSession = Depends(get_db),
) -> List[SupportActivityItem]:
    """
    Pagos confirmados, cambios de estado o de plan y meses de cortesía hechos
    desde el panel de plataforma, con el motivo tal cual lo escribimos (P8,
    transparencia). Sólo el Dueño: un cajero no ve la facturación de su patrón.
    """
    return await support_activity_for_tenant(db, current_user.tenant_id)


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

def _webhook_body_doc(model: type[BaseModel]) -> dict:
    """El cuerpo se lee crudo (para verificar la firma); esto lo documenta en OpenAPI."""
    return {
        "requestBody": {
            "required": True,
            "content": {"application/json": {"schema": model.model_json_schema()}},
        }
    }


async def _signed_payload(
    request: Request,
    signature: Optional[str],
    secret: str,
    provider: str,
    model: type[BaseModel],
):
    """Verifica la firma sobre el cuerpo crudo y sólo entonces lo interpreta."""
    body = await request.body()
    verify_webhook_signature(body, signature, secret, provider)
    try:
        return model.model_validate_json(body)
    except ValidationError as exc:
        raise RequestValidationError(exc.errors()) from exc


@router.post(
    "/webhooks/spei/payment-confirmation",
    response_model=WebhookConfirmationResponse,
    status_code=status.HTTP_200_OK,
    summary="Webhook de confirmación de pago SPEI",
    description=(
        "Recibe las transferencias SPEI vía STP. Exige la firma HMAC-SHA256 del cuerpo "
        f"en `{SIGNATURE_HEADER}` con el secreto `SPEI_WEBHOOK_SECRET`."
    ),
    openapi_extra=_webhook_body_doc(SpeiWebhookPayload),
)
async def webhook_spei_payment_confirmation(
    request: Request,
    x_nexus_signature: Optional[str] = Header(None, alias=SIGNATURE_HEADER),
    db: AsyncSession = Depends(get_db),
) -> WebhookConfirmationResponse:
    """Liquida la factura y reactiva la cuenta si la firma, la referencia y el monto cuadran."""
    payload = await _signed_payload(
        request, x_nexus_signature, settings.SPEI_WEBHOOK_SECRET, "SPEI", SpeiWebhookPayload,
    )
    service = SubscriptionService(db)
    return await service.process_spei_webhook(payload)


@router.post(
    "/webhooks/oxxo/payment-confirmation",
    response_model=WebhookConfirmationResponse,
    status_code=status.HTTP_200_OK,
    summary="Webhook de confirmación de pago OXXO",
    description=(
        "Recibe los pagos liquidados en tiendas OXXO. Exige la firma HMAC-SHA256 del cuerpo "
        f"en `{SIGNATURE_HEADER}` con el secreto `OXXO_WEBHOOK_SECRET`."
    ),
    openapi_extra=_webhook_body_doc(OxxoWebhookPayload),
)
async def webhook_oxxo_payment_confirmation(
    request: Request,
    x_nexus_signature: Optional[str] = Header(None, alias=SIGNATURE_HEADER),
    db: AsyncSession = Depends(get_db),
) -> WebhookConfirmationResponse:
    """Liquida la factura y reactiva la cuenta si la firma, la referencia y el monto cuadran."""
    payload = await _signed_payload(
        request, x_nexus_signature, settings.OXXO_WEBHOOK_SECRET, "OXXO", OxxoWebhookPayload,
    )
    service = SubscriptionService(db)
    return await service.process_oxxo_webhook(payload)
