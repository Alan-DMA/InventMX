# Importación de módulos de fecha, hora y cálculo temporal
from datetime import date, datetime, timedelta, timezone
# Importación de precisión decimal para montos en Pesos Mexicanos
from decimal import Decimal
# Importación de tipado estático
from typing import Any, Dict, List, Optional
# Importación de identificadores UUID
import uuid

# Importación de excepciones HTTP de FastAPI
from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de modelos y reglas de dominio
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan, TenantStatus
from app.modules.saas_billing.domain.subscription_invoice import (
    SaasPaymentMethod,
    SubscriptionInvoice,
    SubscriptionInvoiceStatus,
)
from app.modules.saas_billing.domain.subscription_plan import AVAILABLE_PLANS, PlanTier
from app.modules.saas_billing.repositories.subscription_repository import SubscriptionRepository
from app.modules.saas_billing.schemas.saas_schemas import (
    GeneratePaymentMethodRequest,
    InvoiceItemResponse,
    InvoiceListResponse,
    InvoiceSummary,
    OxxoWebhookPayload,
    PaymentMethodDetailsResponse,
    PlanChangeDetail,
    PlanResponse,
    SpeiWebhookPayload,
    SubscriptionChangePlanRequest,
    SubscriptionChangePlanResponse,
    SubscriptionResponse,
    SubscriptionUsageResponse,
    SubscriptionUsageStats,
    WebhookConfirmationResponse,
)


class SubscriptionService:
    """
    Servicio de Dominio y Lógica de Negocio para Facturación SaaS y Ciclo de Vida de Suscripción.
    Implementa la máquina de estados de morosidad (ACTIVE -> SOFT_LOCK -> HARD_LOCK),
    validación de capacidades para cambio de plan, y conciliación bancaria automatizada SPEI/OXXO.
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repo = SubscriptionRepository(session)

    async def get_plans(self) -> List[PlanResponse]:
        """Retorna el catálogo oficial de planes con sus características y tarifas en MXN."""
        return [PlanResponse(**plan.model_dump()) for plan in AVAILABLE_PLANS.values()]

    async def get_subscription(self, tenant_id: uuid.UUID) -> SubscriptionResponse:
        """
        Consulta el estado actual de la suscripción del comercio junto con sus estadísticas de uso.
        """
        tenant = await self.repo.get_tenant_by_id(tenant_id)
        if not tenant:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Comercio no encontrado en el sistema.",
            )

        plan_tier = AVAILABLE_PLANS.get(tenant.plan_id, AVAILABLE_PLANS[TenantPlan.EMPRENDEDOR])

        # Obtener métricas de uso reales
        products_count = await self.repo.count_tenant_products(tenant_id)
        users_count = await self.repo.count_tenant_users(tenant_id)

        # Periodo del mes en curso
        now = datetime.now(timezone.utc)
        month_start = datetime(now.year, now.month, 1, tzinfo=timezone.utc)
        if now.month == 12:
            month_end = datetime(now.year + 1, 1, 1, tzinfo=timezone.utc)
        else:
            month_end = datetime(now.year, now.month + 1, 1, tzinfo=timezone.utc)

        monthly_sales = await self.repo.get_tenant_monthly_sales(tenant_id, month_start, month_end)

        stats = SubscriptionUsageStats(
            products_count=products_count,
            products_limit=plan_tier.max_products if plan_tier.max_products > 0 else 999999,
            monthly_sales_mxn=monthly_sales,
            monthly_sales_limit_mxn=plan_tier.max_monthly_sales_mxn,
            users_count=users_count,
            users_limit=plan_tier.max_users if plan_tier.max_users > 0 else 999999,
        )

        return SubscriptionResponse(
            id=tenant.id,
            tenant_name=tenant.name,
            slug=tenant.slug,
            plan=tenant.plan_id,
            status=tenant.status,
            current_period_start=month_start,
            current_period_end=month_end,
            monthly_fee_mxn=plan_tier.monthly_price_mxn,
            usage_stats=stats,
        )

    async def change_plan(
        self,
        tenant_id: uuid.UUID,
        request: SubscriptionChangePlanRequest,
    ) -> SubscriptionChangePlanResponse:
        """
        Procesa el cambio de plan validando que el uso actual no viole los límites del nuevo plan.
        """
        tenant = await self.repo.get_tenant_by_id(tenant_id)
        if not tenant:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Comercio no encontrado.")

        new_plan_tier = AVAILABLE_PLANS.get(request.new_plan)
        if not new_plan_tier:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Plan especificado no válido.")

        # 1. Validar degradación de límites de productos
        products_count = await self.repo.count_tenant_products(tenant_id)
        if new_plan_tier.max_products != -1 and products_count > new_plan_tier.max_products:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail={
                    "code": "DOWNGRADE_BLOCKED_BY_USAGE",
                    "message": f"No puedes cambiar al {new_plan_tier.name}. Tienes {products_count} productos y el límite es {new_plan_tier.max_products}.",
                },
            )

        # 2. Validar degradación de límites de usuarios
        users_count = await self.repo.count_tenant_users(tenant_id)
        if new_plan_tier.max_users != -1 and users_count > new_plan_tier.max_users:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail={
                    "code": "DOWNGRADE_BLOCKED_BY_USAGE",
                    "message": f"No puedes cambiar al {new_plan_tier.name}. Tienes {users_count} usuarios y el límite es {new_plan_tier.max_users}.",
                },
            )

        old_plan = tenant.plan_id
        effective_date = datetime.now(timezone.utc)

        # 3. Actualizar el plan del comercio
        await self.repo.update_tenant_plan_and_status(tenant_id=tenant_id, plan=request.new_plan)
        await self.session.commit()

        updated_sub = await self.get_subscription(tenant_id)

        return SubscriptionChangePlanResponse(
            subscription=updated_sub,
            plan_change=PlanChangeDetail(
                from_plan=old_plan,
                to_plan=request.new_plan,
                effective_date=effective_date,
                prorated_amount_mxn=new_plan_tier.monthly_price_mxn if request.change_immediately else Decimal("0.00"),
            ),
        )

    async def list_invoices(
        self,
        tenant_id: uuid.UUID,
        status_filter: Optional[SubscriptionInvoiceStatus] = None,
        year: Optional[int] = None,
        month: Optional[int] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> InvoiceListResponse:
        """Lista las facturas del comercio con paginación y sumario acumulado."""
        offset = (page - 1) * page_size
        invoices, total = await self.repo.list_invoices(
            tenant_id=tenant_id,
            status_filter=status_filter,
            year=year,
            month=month,
            limit=page_size,
            offset=offset,
        )
        summary_data = await self.repo.get_invoices_summary(tenant_id)

        items = [InvoiceItemResponse.model_validate(inv) for inv in invoices]
        return InvoiceListResponse(
            items=items,
            summary=InvoiceSummary(**summary_data),
            total=total,
        )

    async def get_invoice_detail(
        self,
        invoice_id: uuid.UUID,
        tenant_id: uuid.UUID,
    ) -> InvoiceItemResponse:
        """Recupera el detalle de una factura específica asegurando aislamiento tenant."""
        invoice = await self.repo.get_invoice_by_id(invoice_id, tenant_id=tenant_id)
        if not invoice:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Factura no encontrada.")
        return InvoiceItemResponse.model_validate(invoice)

    async def generate_payment_method(
        self,
        invoice_id: uuid.UUID,
        tenant_id: uuid.UUID,
        request: GeneratePaymentMethodRequest,
    ) -> PaymentMethodDetailsResponse:
        """
        Genera referencias y datos bancarios para efectuar el pago de una factura pendiente.
        """
        invoice = await self.repo.get_invoice_by_id(invoice_id, tenant_id=tenant_id)
        if not invoice:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Factura no encontrada.")

        if invoice.status == SubscriptionInvoiceStatus.PAID:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="La factura ya se encuentra pagada.",
            )

        # Generar referencia alfanumérica determinista si no existe
        if not invoice.payment_reference:
            ref_num = f"NX{datetime.now().strftime('%Y%m%d')}{str(invoice.id)[:8].upper()}"
            invoice.payment_reference = ref_num

        now = datetime.now(timezone.utc)
        expires_at = now + timedelta(days=3 if request.payment_method == SaasPaymentMethod.SPEI else 15)

        if request.payment_method == SaasPaymentMethod.SPEI:
            # Generar CLABE interbancaria personalizada de 18 dígitos: 646 (STP) + 180 (Plaza) + 11 dígitos + 1 control
            clean_digits = "".join(filter(str.isdigit, str(invoice.id.int)))[:11].ljust(11, "0")
            clabe_18 = f"646180{clean_digits}4"
            invoice.clabe = clabe_18
            invoice.payment_method = SaasPaymentMethod.SPEI
            await self.session.commit()

            return PaymentMethodDetailsResponse(
                payment_method=SaasPaymentMethod.SPEI,
                reference_id=invoice.payment_reference,
                amount_mxn=invoice.amount_mxn,
                clabe=clabe_18,
                bank_name="STP",
                concept=f"Nexus Plan {invoice.plan.value}",
                expires_at=expires_at,
            )

        elif request.payment_method == SaasPaymentMethod.OXXO:
            # Generar referencia numérica de 14 dígitos para OXXO Pay
            oxxo_num = f"9876{str(invoice.id.int)[:10].ljust(10, '0')}"
            invoice.oxxo_reference = oxxo_num
            invoice.payment_method = SaasPaymentMethod.OXXO
            await self.session.commit()

            return PaymentMethodDetailsResponse(
                payment_method=SaasPaymentMethod.OXXO,
                reference_id=invoice.payment_reference,
                amount_mxn=invoice.amount_mxn,
                barcode=f"750{oxxo_num}",
                reference_number=oxxo_num,
                expires_at=expires_at,
            )

        else:
            invoice.payment_method = SaasPaymentMethod.CARD
            await self.session.commit()
            return PaymentMethodDetailsResponse(
                payment_method=SaasPaymentMethod.CARD,
                reference_id=invoice.payment_reference,
                amount_mxn=invoice.amount_mxn,
                concept=f"Nexus Plan {invoice.plan.value}",
                expires_at=expires_at,
            )

    async def process_spei_webhook(
        self,
        payload: SpeiWebhookPayload,
    ) -> WebhookConfirmationResponse:
        """
        Procesa el webhook de confirmación bancaria SPEI liquidando la factura y reactivando la cuenta.
        """
        # Registrar evento en la bitácora
        await self.repo.log_webhook_event(
            provider="SPEI",
            reference_id=payload.reference_id,
            payload=payload.model_dump(mode="json"),
            processed=False,
        )

        # Buscar la factura por la referencia o CLABE
        invoice = await self.repo.get_invoice_by_reference(payload.reference_id)
        if not invoice:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"error": "Payment reference not found"},
            )

        if invoice.status == SubscriptionInvoiceStatus.PAID:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail={"error": "Payment already processed"},
            )

        # Marcar la factura como pagada
        invoice.status = SubscriptionInvoiceStatus.PAID
        invoice.paid_at = payload.payment_date or datetime.now(timezone.utc)

        # Reactivar el comercio si estaba en SOFT_LOCK o HARD_LOCK
        tenant = await self.repo.get_tenant_by_id(invoice.tenant_id)
        if tenant and tenant.status in [TenantStatus.SOFT_LOCK, TenantStatus.HARD_LOCK]:
            tenant.status = TenantStatus.ACTIVE
            tenant.updated_at = datetime.now(timezone.utc)

        await self.session.commit()

        return WebhookConfirmationResponse(
            status="PAYMENT_CONFIRMED",
            invoice_id=invoice.id,
            subscription_status=tenant.status if tenant else TenantStatus.ACTIVE,
        )

    async def process_oxxo_webhook(
        self,
        payload: OxxoWebhookPayload,
    ) -> WebhookConfirmationResponse:
        """
        Procesa el webhook de confirmación de pago en OXXO Pay.
        """
        await self.repo.log_webhook_event(
            provider="OXXO",
            reference_id=payload.reference_id,
            payload=payload.model_dump(mode="json"),
            processed=False,
        )

        invoice = await self.repo.get_invoice_by_reference(payload.reference_id)
        if not invoice:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"error": "Payment reference not found"},
            )

        if invoice.status == SubscriptionInvoiceStatus.PAID:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail={"error": "Payment already processed"},
            )

        invoice.status = SubscriptionInvoiceStatus.PAID
        invoice.paid_at = payload.payment_date or datetime.now(timezone.utc)

        tenant = await self.repo.get_tenant_by_id(invoice.tenant_id)
        if tenant and tenant.status in [TenantStatus.SOFT_LOCK, TenantStatus.HARD_LOCK]:
            tenant.status = TenantStatus.ACTIVE
            tenant.updated_at = datetime.now(timezone.utc)

        await self.session.commit()

        return WebhookConfirmationResponse(
            status="PAYMENT_CONFIRMED",
            invoice_id=invoice.id,
            subscription_status=tenant.status if tenant else TenantStatus.ACTIVE,
        )
