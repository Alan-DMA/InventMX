from pydantic import BaseModel, Field
from uuid import UUID
from decimal import Decimal
from typing import Optional, List, Literal
from datetime import datetime

# --- Ítem de Venta ---
class SaleItemCreate(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(..., gt=0)
    unit_price_usd: Decimal = Field(..., ge=0)

class SaleItemResponse(BaseModel):
    product_id: UUID
    quantity: Decimal
    unit_cost_usd: Decimal
    unit_price_usd: Decimal

    class Config:
        from_attributes = True


# --- Pago de Venta ---
class SalePaymentCreate(BaseModel):
    payment_method: str = Field(..., min_length=1)  # EFECTIVO_USD, EFECTIVO_VES, PAGO_MOVIL, ZELLE, TARJETA
    amount_usd: Decimal = Field(..., ge=0)
    amount_ves: Decimal = Field(..., ge=0)
    reference_number: Optional[str] = None

class SalePaymentResponse(BaseModel):
    payment_method: str
    amount_usd: Decimal
    amount_ves: Decimal
    reference_number: Optional[str] = None

    class Config:
        from_attributes = True


# --- Creación y Actualización de Venta ---
class SaleCreate(BaseModel):
    seller_id: Optional[UUID] = None
    items: List[SaleItemCreate] = Field(..., min_length=1)

class SaleStatusTransition(BaseModel):
    # M-07: Literal valida el valor exacto en la capa de schema (antes de llegar al endpoint)
    new_status: Literal["PENDING_PAYMENT", "PAID", "COMPLETED", "CANCELLED", "REFUNDED"] = Field(
        ..., description="Nuevo estado de la venta. Solo se permiten transiciones válidas."
    )


# --- Respuesta de Venta ---
class SaleResponse(BaseModel):
    id: UUID
    tenant_id: UUID
    user_id: UUID
    seller_id: Optional[UUID] = None
    exchange_rate_applied: Decimal
    status: str
    total_usd: Decimal
    commission_amount_usd: Decimal
    created_at: datetime
    updated_at: datetime
    items: List[SaleItemResponse] = []
    payments: List[SalePaymentResponse] = []

    class Config:
        from_attributes = True
