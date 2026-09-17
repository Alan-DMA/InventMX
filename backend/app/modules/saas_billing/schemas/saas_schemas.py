# Importación de fecha y hora
from datetime import date, datetime
# Importación de precisión decimal para importes monetarios en MXN
from decimal import Decimal
# Importación de tipado estático
from typing import Any, Dict, List, Optional
# Importación de identificadores UUID
import uuid

# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, EmailStr, Field

# Importación de enums de dominio
from app.modules.auth_tenancy.domain.tenant import TenantPlan, TenantStatus
from app.modules.saas_billing.domain.subscription_invoice import (
    SaasPaymentMethod,
    SubscriptionInvoiceStatus,
)


class PlanResponse(BaseModel):
    """Esquema de respuesta para detalles de un plan disponible."""
    model_config = ConfigDict(from_attributes=True)

    id: TenantPlan = Field(..., description="Identificador único del plan")
    name: str = Field(..., description="Nombre comercial del plan")
    description: str = Field(..., description="Descripción detallada de la propuesta de valor")
    monthly_price_mxn: Decimal = Field(..., description="Costo mensual en Pesos Mexicanos")
    annual_price_mxn: Decimal = Field(..., description="Costo anual con descuento en MXN")
    max_users: int = Field(..., description="Usuarios permitidos (-1 ilimitado)")
    max_warehouses: int = Field(..., description="Sucursales permitidas (-1 ilimitado)")
    max_products: int = Field(..., description="Límite de catálogo (-1 ilimitado)")
    max_monthly_sales_mxn: Optional[Decimal] = Field(None, description="Límite mensual de ventas")
    cash_registers_allowed: bool = Field(..., description="Soporte para turnos de caja y arqueos")
    commissions_allowed: bool = Field(..., description="Soporte para cálculo de comisiones")
    advanced_reports_allowed: bool = Field(..., description="Soporte para analítica financiera y COGS")
    b2b_community_allowed: bool = Field(..., description="Soporte para red B2B comunitaria")
    whatsapp_catalog_allowed: bool = Field(..., description="Soporte para catálogo en línea de WhatsApp")


class SubscriptionUsageStats(BaseModel):
    """Métricas de uso actual frente a los límites del plan contratado."""
    products_count: int = Field(..., description="Cantidad actual de productos en el catálogo")
    products_limit: int = Field(..., description="Límite máximo de productos del plan")
    monthly_sales_mxn: Decimal = Field(..., description="Ventas totales acumuladas en el mes actual en MXN")
    monthly_sales_limit_mxn: Optional[Decimal] = Field(None, description="Límite de ventas mensuales permitido")
    users_count: int = Field(..., description="Cantidad de usuarios registrados")
    users_limit: int = Field(..., description="Límite de usuarios del plan")


class SubscriptionResponse(BaseModel):
    """Detalle completo del estado de la suscripción del tenant en sesión."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID = Field(..., description="Identificador del tenant o suscripción")
    tenant_name: str = Field(..., description="Nombre de la empresa o tienda")
    slug: str = Field(..., description="Slug público de la tienda")
    plan: TenantPlan = Field(..., description="Nivel de plan actualmente activo")
    status: TenantStatus = Field(..., description="Estado de morosidad (ACTIVE, SOFT_LOCK, HARD_LOCK)")
    current_period_start: datetime = Field(..., description="Fecha de inicio del ciclo actual")
    current_period_end: datetime = Field(..., description="Fecha de corte o renovación del ciclo")
    monthly_fee_mxn: Decimal = Field(..., description="Tarifa mensual actual en MXN")
    usage_stats: SubscriptionUsageStats = Field(..., description="Estadísticas de consumo y capacidad")


class SubscriptionChangePlanRequest(BaseModel):
    """Petición para solicitar actualización o degradación de plan SaaS."""
    new_plan: TenantPlan = Field(..., description="Nuevo nivel de plan deseado")
    change_immediately: bool = Field(default=False, description="Aplica inmediatamente o al vencer el periodo")
    reason: Optional[str] = Field(None, max_length=200, description="Motivo del cambio de plan")


class PlanChangeDetail(BaseModel):
    """Detalle del cambio de plan procesado."""
    from_plan: TenantPlan
    to_plan: TenantPlan
    effective_date: datetime
    prorated_amount_mxn: Optional[Decimal] = None


class SubscriptionChangePlanResponse(BaseModel):
    """Respuesta a la solicitud de cambio de plan."""
    subscription: SubscriptionResponse
    plan_change: PlanChangeDetail


class MetricUsage(BaseModel):
    """Uso y porcentaje para una métrica específica."""
    current: Decimal
    limit: Optional[Decimal] = None
    percentage_used: float = Field(0.0, description="Porcentaje consumido de 0 a 100")


class SubscriptionUsageResponse(BaseModel):
    """Reporte detallado de uso y alertas de límites de plan."""
    current_period: Dict[str, date]
    metrics: Dict[str, Any]
    warnings: List[Dict[str, str]]


class InvoiceItemResponse(BaseModel):
    """Resumen de factura para listas paginadas."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    plan: TenantPlan
    amount_mxn: Decimal
    payment_method: SaasPaymentMethod
    status: SubscriptionInvoiceStatus
    period_start: date
    period_end: date
    payment_reference: Optional[str] = None
    clabe: Optional[str] = None
    oxxo_reference: Optional[str] = None
    paid_at: Optional[datetime] = None
    created_at: datetime


class InvoiceSummary(BaseModel):
    """Resumen acumulado del historial de facturas."""
    total_paid_mxn: Decimal = Field(Decimal("0.00"), description="Total pagado históricamente")
    pending_amount_mxn: Decimal = Field(Decimal("0.00"), description="Importe total adeudado pendiente")
    overdue_count: int = Field(0, description="Cantidad de facturas vencidas")


class InvoiceListResponse(BaseModel):
    """Respuesta paginada del historial de facturas."""
    items: List[InvoiceItemResponse]
    summary: InvoiceSummary
    total: int


class GeneratePaymentMethodRequest(BaseModel):
    """Petición para obtener datos para efectuar el pago de una factura."""
    payment_method: SaasPaymentMethod = Field(..., description="Método deseado: SPEI, OXXO o CARD")
    customer_email: Optional[EmailStr] = Field(None, description="Correo electrónico para envío de ficha de pago")


class PaymentMethodDetailsResponse(BaseModel):
    """Instrucciones y referencias para completar el pago."""
    payment_method: SaasPaymentMethod
    reference_id: str
    amount_mxn: Decimal
    clabe: Optional[str] = None
    bank_name: Optional[str] = None
    concept: Optional[str] = None
    barcode: Optional[str] = None
    reference_number: Optional[str] = None
    expires_at: datetime


class SpeiWebhookPayload(BaseModel):
    """Payload de notificación automática de pago interbancario SPEI."""
    reference_id: str = Field(..., description="ID de referencia del pago conciliable con la factura")
    amount: Decimal = Field(..., description="Monto transferido en Pesos Mexicanos")
    payment_date: datetime = Field(..., description="Fecha y hora de acreditación bancaria")
    bank_confirmation: str = Field(..., description="Clave de rastreo bancaria emitida por Banxico/STP")
    sender_account: Optional[str] = Field(None, description="Cuenta o tarjeta de procedencia")
    sender_bank: Optional[str] = Field(None, description="Institución bancaria de procedencia")
    webhook_signature: Optional[str] = Field(None, description="Firma criptográfica de autenticidad")


class OxxoWebhookPayload(BaseModel):
    """Payload de notificación automática de pago en efectivo en tienda OXXO."""
    reference_id: str = Field(..., description="Referencia numérica generada para OXXO Pay")
    amount: Decimal = Field(..., description="Monto cobrado en caja OXXO en MXN")
    payment_date: datetime = Field(..., description="Fecha y hora del cobro en la sucursal OXXO")
    store_confirmation: str = Field(..., description="Folio de ticket o autorización OXXO")
    store_id: Optional[str] = Field(None, description="Número de tienda OXXO")
    barcode: Optional[str] = Field(None, description="Código de barras escaneado")
    webhook_signature: Optional[str] = Field(None, description="Firma criptográfica de autenticidad")


class WebhookConfirmationResponse(BaseModel):
    """Respuesta estándar para confirmación de recepción de webhook de pago."""
    status: str = Field("PAYMENT_CONFIRMED", description="Estado de confirmación de pago")
    invoice_id: uuid.UUID = Field(..., description="ID de la factura liquidada")
    subscription_status: TenantStatus = Field(..., description="Estado resultante de la suscripción (ACTIVE)")
