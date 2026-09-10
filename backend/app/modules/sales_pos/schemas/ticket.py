# Importación de marcas de fecha
from datetime import datetime
# Importación de precisión decimal
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de UUID
import uuid
# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field


class TicketSettingsUpdateRequest(BaseModel):
    """
    Esquema de solicitud para actualizar la configuración de impresión de tickets térmicos (RF-08).
    """
    model_config = ConfigDict(from_attributes=True)

    # Nombre comercial que se imprime en la cabecera del ticket
    business_name: Optional[str] = Field(
        default=None,
        max_length=150,
        description="Nombre comercial que encabeza el ticket de venta",
    )

    # Razón social del negocio
    legal_name: Optional[str] = Field(
        default=None,
        max_length=150,
        description="Razón social o denominación jurídica del establecimiento",
    )

    # RFC simplificado impreso en el ticket
    rfc: Optional[str] = Field(
        default=None,
        max_length=13,
        description="Registro Federal de Contribuyentes para identificación comercial",
    )

    # Dirección o sucursal del comercio
    address: Optional[str] = Field(
        default=None,
        max_length=500,
        description="Domicilio físico de la sucursal",
    )

    # Teléfono o WhatsApp de atención al cliente
    phone: Optional[str] = Field(
        default=None,
        max_length=30,
        description="Teléfono de contacto para el ticket",
    )

    # Correo electrónico de contacto
    email: Optional[str] = Field(
        default=None,
        max_length=100,
        description="Correo electrónico comercial",
    )

    # Mensaje de despedida o políticas de cambio al pie del ticket
    footer_message: Optional[str] = Field(
        default=None,
        max_length=500,
        description="Mensaje de cortesía o políticas de cambio al pie de ticket",
    )

    # Ancho del papel térmico en milímetros (58 o 80)
    paper_width_mm: Optional[int] = Field(
        default=None,
        description="Ancho en milímetros del rollo térmico (58mm = 32 col, 80mm = 48 col)",
    )

    # Bandera para mostrar la leyenda de ahorro total
    show_savings: Optional[bool] = Field(
        default=None,
        description="Habilitar bloque de ahorro por promociones y descuentos",
    )

    # Bandera para imprimir el nombre del cajero
    show_cashier_name: Optional[bool] = Field(
        default=None,
        description="Habilitar impresión del nombre del cajero en turno",
    )

    # Bandera para desglosar impuestos informativos
    show_taxes: Optional[bool] = Field(
        default=None,
        description="Habilitar desglose informativo de impuestos",
    )


class TicketSettingsResponse(BaseModel):
    """
    Esquema de salida para la configuración de tickets térmicos del comercio.
    """
    model_config = ConfigDict(from_attributes=True)

    tenant_id: uuid.UUID
    business_name: Optional[str] = None
    legal_name: Optional[str] = None
    rfc: Optional[str] = None
    address: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    footer_message: str
    paper_width_mm: int
    show_savings: bool
    show_cashier_name: bool
    show_taxes: bool
    updated_at: datetime


class TicketLineItemPayload(BaseModel):
    """
    Esquema para una partida individual impresa en el comprobante simplificado.
    """
    model_config = ConfigDict(from_attributes=True)

    quantity: Decimal
    product_name: str
    unit_price_mxn: Decimal
    discount_mxn: Decimal
    total_mxn: Decimal


class TicketPaymentPayload(BaseModel):
    """
    Esquema para el desglose de un método de pago liquidado en el ticket.
    """
    model_config = ConfigDict(from_attributes=True)

    payment_method: str
    amount_paid_mxn: Decimal
    reference_code: Optional[str] = None


class TicketPayloadResponse(BaseModel):
    """
    Esquema completo para la Nota de Venta / Ticket Térmico POS (RF-08 / Const. Art. 1.2.8).
    Provee tanto los campos estructurados para renderizado UI/ESC-POS como el texto plano monoespaciado pre-formateado.
    """
    model_config = ConfigDict(from_attributes=True)

    folio: str
    created_at: datetime
    cashier_name: Optional[str] = None
    business_name: str
    legal_name: Optional[str] = None
    rfc: Optional[str] = None
    address: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    paper_width_mm: int
    items: List[TicketLineItemPayload]
    subtotal_mxn: Decimal
    discount_mxn: Decimal
    tax_mxn: Decimal
    total_mxn: Decimal
    amount_paid_mxn: Decimal
    change_returned_mxn: Decimal
    savings_mxn: Decimal
    payments: List[TicketPaymentPayload]
    footer_message: str
    formatted_text: str = Field(
        ...,
        description="Texto monoespaciado pre-alineado listo para enviar al puerto de la impresora térmica",
    )
