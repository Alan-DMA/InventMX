# Importación de marcas temporales
from datetime import datetime
# Importación de tipos decimales
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field

# Importación de modelos y esquemas de pago
from app.modules.sales_pos.domain.sale import SaleStatus
from app.modules.sales_pos.schemas.payment import PaymentRequest, PaymentResponse


class SaleItemRequest(BaseModel):
    """
    Esquema para una partida dentro del carrito de venta en el POS.
    Soporta productos existentes, combos y creación de productos al vuelo (Lazy Loading).
    """
    model_config = ConfigDict(from_attributes=True)

    # Identificador del producto existente en inventario (opcional si es combo o al vuelo)
    product_id: Optional[uuid.UUID] = Field(
        default=None,
        description="ID del producto existente en catálogo",
    )

    # Identificador del combo promocional (opcional)
    combo_id: Optional[uuid.UUID] = Field(
        default=None,
        description="ID del combo promocional",
    )

    # Cantidad a cobrar (admite decimales para productos a granel/peso)
    quantity: Decimal = Field(
        gt=0,
        description="Cantidad vendida en unidades o kilogramos",
    )

    # Precio unitario opcional en Pesos Mexicanos (si es None se toma del producto)
    unit_price_mxn: Optional[Decimal] = Field(
        default=None,
        ge=0,
        description="Precio de venta unitario en $ MXN",
    )

    # Descuento en Pesos Mexicanos aplicado a esta partida
    discount_mxn: Decimal = Field(
        default=Decimal("0.00"),
        ge=0,
        description="Descuento en $ MXN para este ítem",
    )

    # Bandera de producto al vuelo (Lazy Loading RF-09 / Const. Art. 7.3)
    is_on_the_fly: bool = Field(
        default=False,
        description="Indica si es un producto no catalogado creado al vuelo",
    )

    # Nombre comercial si el producto es creado al vuelo
    on_the_fly_name: Optional[str] = Field(
        default=None,
        min_length=1,
        max_length=255,
        description="Nombre del producto no catalogado para Lazy Loading",
    )

    # Código de barras opcional si el producto es creado al vuelo
    on_the_fly_barcode: Optional[str] = Field(
        default=None,
        max_length=50,
        description="Código de barras escaneado al vuelo",
    )

    # Costo de adquisición unitario opcional si se conoce al vuelo
    on_the_fly_cost_mxn: Optional[Decimal] = Field(
        default=Decimal("0.00"),
        ge=0,
        description="Costo unitario del producto al vuelo",
    )


class SaleCheckoutRequest(BaseModel):
    """
    Esquema de solicitud para procesar el Checkout atómico en el Punto de Venta con soporte de pagos mixtos (RF-09, RF-12, RF-13, RF-14).
    """
    model_config = ConfigDict(from_attributes=True)

    # Almacén de donde se descontarán las existencias físicas
    warehouse_id: uuid.UUID = Field(
        description="ID del almacén físico para descuento de inventario",
    )

    # Cliente opcional asociado a la venta
    client_id: Optional[uuid.UUID] = Field(
        default=None,
        description="ID opcional del cliente",
    )

    # Partidas o artículos incluidos en el carrito
    items: List[SaleItemRequest] = Field(
        min_length=1,
        description="Lista de productos o combos a cobrar",
    )

    # Desglose de pagos realizados (si se omite, se asume pago exacto en efectivo CASH_MXN)
    payments: Optional[List[PaymentRequest]] = Field(
        default=None,
        description="Lista de métodos de pago aplicados a la venta (RF-13, RF-14)",
    )

    # Bandera para admitir pagos parciales o diferidos (estado PENDING_PAYMENT)
    allow_partial_payment: bool = Field(
        default=False,
        description="Permite registrar la venta en estado diferido PENDING_PAYMENT si el pago inicial es parcial",
    )

    # Descuento global a nivel de ticket
    discount_mxn: Decimal = Field(
        default=Decimal("0.00"),
        ge=0,
        description="Descuento general aplicado al total de la venta en $ MXN",
    )

    # Notas u observaciones adicionales para la nota de venta
    notes: Optional[str] = Field(
        default=None,
        max_length=500,
        description="Notas u observaciones de la nota de venta",
    )


class SaleItemResponse(BaseModel):
    """
    Esquema de respuesta para una partida individual de venta con snapshot congelado.
    """
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    sale_id: uuid.UUID
    product_id: Optional[uuid.UUID] = None
    combo_id: Optional[uuid.UUID] = None
    product_name: str
    product_sku: Optional[str] = None
    quantity: Decimal
    unit_price_mxn: Decimal
    unit_cost_mxn: Decimal
    subtotal_mxn: Decimal
    discount_mxn: Decimal
    total_mxn: Decimal
    is_on_the_fly: bool
    profit_mxn: Decimal = Field(
        description="Utilidad bruta generada por la partida en $ MXN",
    )
    created_at: datetime


class SaleResponse(BaseModel):
    """
    Esquema de respuesta completa del comprobante / nota de venta POS (RF-08, RF-13, RF-14).
    """
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    cashier_id: uuid.UUID
    warehouse_id: uuid.UUID
    client_id: Optional[uuid.UUID] = None
    folio: str
    status: SaleStatus
    subtotal_mxn: Decimal
    discount_mxn: Decimal
    tax_mxn: Decimal
    total_mxn: Decimal
    total_cost_mxn: Decimal
    gross_profit_mxn: Decimal = Field(
        description="Utilidad bruta total de la venta (total_mxn - total_cost_mxn)",
    )
    payment_method_type: Optional[str] = Field(
        default="CASH_MXN",
        description="Método de pago o 'MIXED' si se dividió el pago",
    )
    amount_paid_mxn: Decimal = Field(
        default=Decimal("0.00"),
        description="Monto total pagado por el cliente",
    )
    change_returned_mxn: Decimal = Field(
        default=Decimal("0.00"),
        description="Monto de vuelto o cambio devuelto al cliente",
    )
    notes: Optional[str] = None
    items: List[SaleItemResponse]
    payments: List[PaymentResponse] = Field(
        default_factory=list,
        description="Desglose contable de los pagos registrados",
    )
    created_at: datetime
    updated_at: datetime


class SaleCancelRequest(BaseModel):
    """
    Esquema para anulación o cancelación de una venta registrada.
    """
    model_config = ConfigDict(from_attributes=True)

    reason: str = Field(
        min_length=3,
        max_length=255,
        description="Motivo de cancelación o devolución de la venta",
    )
