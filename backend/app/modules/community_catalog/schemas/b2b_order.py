# Importación de precisión decimal para Pesos Mexicanos
from datetime import datetime
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field

from app.modules.community_catalog.domain.b2b_order import B2BDeliveryType, B2BOrderStatus


class B2BOrderItemCreateRequest(BaseModel):
    """Partida individual en la solicitud de pedido B2B."""
    b2b_listing_id: uuid.UUID = Field(description="ID de la oferta mayorista")
    quantity: Decimal = Field(gt=0, description="Cantidad de piezas solicitadas")


class B2BOrderCreateRequest(BaseModel):
    """Solicitud de emisión de pedido mayorista entre comercios (RF-27)."""
    seller_tenant_id: uuid.UUID = Field(description="ID del comercio vendedor al que se solicita el pedido")
    delivery_type: B2BDeliveryType = Field(default=B2BDeliveryType.PICKUP, description="Modalidad de entrega")
    delivery_address: Optional[str] = Field(default=None, max_length=300, description="Dirección si es a domicilio")
    notes: Optional[str] = Field(default=None, max_length=500, description="Notas para el vendedor")
    items: List[B2BOrderItemCreateRequest] = Field(min_length=1, description="Lista de partidas solicitadas")


class B2BOrderItemResponse(BaseModel):
    """Partida detallada de un pedido B2B."""
    id: uuid.UUID = Field(description="ID del renglón")
    b2b_listing_id: uuid.UUID = Field(description="ID de la oferta")
    product_id: uuid.UUID = Field(description="ID del producto físico")
    product_name: str = Field(description="Nombre del producto")
    quantity: Decimal = Field(description="Cantidad de piezas")
    unit_price_mxn: Decimal = Field(description="Precio unitario en $ MXN")
    subtotal_mxn: Decimal = Field(description="Subtotal en $ MXN")

    model_config = ConfigDict(from_attributes=True)


class B2BOrderResponse(BaseModel):
    """Respuesta completa del pedido mayorista B2B (RF-27 / Const. Art. 7.5)."""
    id: uuid.UUID = Field(description="ID del pedido B2B")
    order_number: str = Field(description="Folio de pedido (ej: B2B-2026-0001)")
    buyer_tenant_id: uuid.UUID = Field(description="Comercio comprador")
    buyer_store_name: str = Field(description="Nombre de la tienda compradora")
    seller_tenant_id: uuid.UUID = Field(description="Comercio vendedor")
    seller_store_name: str = Field(description="Nombre de la tienda proveedora")
    status: B2BOrderStatus = Field(description="Estado transaccional")
    total_mxn: Decimal = Field(description="Importe total en Pesos Mexicanos ($ MXN)")
    delivery_type: B2BDeliveryType = Field(description="Modalidad de entrega")
    delivery_address: Optional[str] = Field(default=None)
    notes: Optional[str] = Field(default=None)
    items: List[B2BOrderItemResponse] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class B2BOrderStatusUpdateRequest(BaseModel):
    """Actualización de estado transaccional del pedido por el vendedor o comprador."""
    status: B2BOrderStatus = Field(description="Nuevo estado: ACCEPTED, REJECTED, COMPLETED o CANCELLED")
    notes: Optional[str] = Field(default=None, max_length=500, description="Razón o notas del cambio de estado")
