# Importación de marcas de fecha
from datetime import datetime
# Importación de precisión decimal
from decimal import Decimal
# Importación de tipado estático
from typing import Dict, List, Optional
# Importación de UUID
import uuid
# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field

# Importación de la enumeración de métodos de pago de dominio
from app.modules.sales_pos.domain.payment import PaymentMethod


class PaymentRequest(BaseModel):
    """
    Esquema de entrada para registrar un método de pago en mostrador (RF-13, RF-14).
    """
    model_config = ConfigDict(from_attributes=True)

    # Método de pago (CASH_MXN, SPEI, CODI, CARD_TPV, OTHER)
    payment_method: PaymentMethod = Field(
        default=PaymentMethod.CASH_MXN,
        description="Método contable de liquidación en caja",
    )

    # Importe monetario pagado en Pesos Mexicanos ($ MXN)
    amount_paid_mxn: Decimal = Field(
        ...,
        gt=0,
        description="Monto monetario entregado por el cliente en $ MXN",
    )

    # Folio o código de autorización externa (opcional)
    reference_code: Optional[str] = Field(
        default=None,
        max_length=100,
        description="Folio de transferencia SPEI, voucher TPV o CoDi",
    )

    # Notas u observaciones adicionales
    notes: Optional[str] = Field(
        default=None,
        max_length=255,
        description="Notas u observaciones del cobro",
    )


class PaymentResponse(BaseModel):
    """
    Esquema de salida para el registro contable de un pago asociado a una venta.
    """
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    sale_id: uuid.UUID
    payment_method: PaymentMethod
    amount_paid_mxn: Decimal
    change_returned_mxn: Decimal
    reference_code: Optional[str] = None
    notes: Optional[str] = None
    created_at: datetime


class BanxicoDenominationBreakdown(BaseModel):
    """
    Desglose óptimo de billetes y monedas del Banco de México para entregar cambio (RF-14 / Const. Art. 7.2).
    """
    # Billetes oficiales: $1000, $500, $200, $100, $50, $20
    bills: Dict[str, int] = Field(
        default_factory=dict,
        description="Cantidad de billetes por denominación",
    )
    # Monedas oficiales: $20, $10, $5, $2, $1, $0.50
    coins: Dict[str, int] = Field(
        default_factory=dict,
        description="Cantidad de monedas por denominación",
    )


class QuickChangeRequest(BaseModel):
    """
    Esquema para la calculadora rápida de vuelto en mostrador (RF-14).
    """
    model_config = ConfigDict(from_attributes=True)

    # Importe total de la venta en Pesos Mexicanos ($ MXN)
    total_mxn: Decimal = Field(
        ...,
        ge=0,
        description="Total neto a cobrar en $ MXN",
    )

    # Monto en efectivo entregado físicamente por el cliente ($ MXN)
    cash_received_mxn: Decimal = Field(
        ...,
        ge=0,
        description="Efectivo entregado por el cliente en $ MXN",
    )


class QuickChangeResponse(BaseModel):
    """
    Esquema de respuesta de la calculadora de cambio con cono monetario Banxico.
    """
    model_config = ConfigDict(from_attributes=True)

    total_mxn: Decimal
    cash_received_mxn: Decimal
    change_mxn: Decimal
    is_exact_payment: bool
    banxico_breakdown: BanxicoDenominationBreakdown
