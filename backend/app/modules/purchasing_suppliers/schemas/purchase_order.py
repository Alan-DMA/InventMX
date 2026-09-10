# Importación de marcas de fecha y tiempo
from datetime import date, datetime
# Importación de precisión decimal
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field

# Importación de enumeraciones de dominio
from app.modules.purchasing_suppliers.domain.purchase_order import PurchaseOrderStatus


class PurchaseOrderItemCreateRequest(BaseModel):
    """
    Renglón de producto solicitado en una Orden de Compra.
    """
    product_id: uuid.UUID = Field(description="ID del producto a comprar")
    quantity_ordered: Decimal = Field(gt=0, description="Cantidad a ordenar (> 0)")
    unit_cost_mxn: Decimal = Field(
        default=Decimal("0.0000"),
        ge=0,
        description="Costo unitario pactado en Pesos Mexicanos ($ MXN)",
    )
    lot_number: Optional[str] = Field(default=None, max_length=50)
    expiry_date: Optional[date] = None


class PurchaseOrderCreateRequest(BaseModel):
    """
    Contrato para registrar una nueva orden de compra a proveedor (RF-15).
    """
    supplier_id: uuid.UUID = Field(description="ID del proveedor")
    warehouse_id: Optional[uuid.UUID] = Field(
        default=None,
        description="Almacén donde se recibirá la mercancía (por defecto el principal)",
    )
    items: List[PurchaseOrderItemCreateRequest] = Field(
        min_length=1,
        description="Lista de productos a ordenar (mínimo 1)",
    )
    expected_delivery_date: Optional[date] = None
    notes: Optional[str] = Field(default=None, max_length=500)


class PurchaseOrderItemResponse(BaseModel):
    """
    Detalle de renglón de orden de compra.
    """
    id: uuid.UUID
    tenant_id: uuid.UUID
    purchase_order_id: uuid.UUID
    product_id: uuid.UUID
    product_name: Optional[str] = None
    product_sku: Optional[str] = None
    quantity_ordered: Decimal
    quantity_received: Decimal
    unit_cost_mxn: Decimal
    subtotal_mxn: Decimal
    lot_number: Optional[str] = None
    expiry_date: Optional[date] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class PurchaseOrderResponse(BaseModel):
    """
    Esquema de respuesta para la cabecera de orden de compra.
    """
    id: uuid.UUID
    tenant_id: uuid.UUID
    supplier_id: uuid.UUID
    supplier_name: Optional[str] = None
    supplier_rfc: Optional[str] = None
    warehouse_id: uuid.UUID
    warehouse_name: Optional[str] = None
    folio: str
    status: PurchaseOrderStatus
    subtotal_mxn: Decimal
    tax_mxn: Decimal
    total_mxn: Decimal
    expected_delivery_date: Optional[date] = None
    received_date: Optional[date] = None
    invoice_reference: Optional[str] = None
    notes: Optional[str] = None
    created_by_user_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    items: List[PurchaseOrderItemResponse] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)


class PurchaseOrderReceiveItemRequest(BaseModel):
    """
    Renglón de producto recepcionado físicamente en almacén.
    """
    purchase_order_item_id: uuid.UUID = Field(description="ID del renglón de la orden")
    quantity_received: Decimal = Field(gt=0, description="Cantidad recibida físicamente (> 0)")
    unit_cost_mxn: Optional[Decimal] = Field(
        default=None,
        ge=0,
        description="Costo unitario real facturado si difiere de lo cotizado",
    )
    lot_number: Optional[str] = Field(default=None, max_length=50)
    expiry_date: Optional[date] = None


class PurchaseOrderReceiveRequest(BaseModel):
    """
    Contrato de solicitud para recepción física de mercancía (RF-15, RF-17).
    """
    items_received: List[PurchaseOrderReceiveItemRequest] = Field(
        min_length=1,
        description="Lista de ítems recepcionados (mínimo 1)",
    )
    received_date: Optional[date] = Field(
        default=None,
        description="Fecha real de entrega/recepción (por defecto hoy)",
    )
    invoice_reference: Optional[str] = Field(
        default=None,
        max_length=100,
        description="Folio de factura o remisión del proveedor",
    )
    notes: Optional[str] = Field(default=None, max_length=300)


class PurchaseOrderReceiveResponse(BaseModel):
    """
    Respuesta tras recepcionar físicamente mercancía de una orden de compra.
    """
    purchase_order: PurchaseOrderResponse
    stock_movements_count: int
    account_payable: Optional[object] = None

