# Importación de precisión decimal para Pesos Mexicanos
from datetime import datetime
from decimal import Decimal
# Importación de tipado estático
from typing import Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field


class B2BListingCreateRequest(BaseModel):
    """Solicitud para publicar una oferta mayorista en el catálogo comunitario (RF-27)."""
    product_id: uuid.UUID = Field(description="ID del producto físico en inventario a ofertar")
    wholesale_price_mxn: Decimal = Field(gt=0, description="Precio unitario de mayoreo en Pesos Mexicanos ($ MXN)")
    min_wholesale_quantity: Decimal = Field(default=Decimal("1.00"), gt=0, description="Lote mínimo de compra")
    available_b2b_stock: Decimal = Field(default=Decimal("10.00"), ge=0, description="Existencias asignadas a mayoreo")
    location_postal_code: Optional[str] = Field(default=None, max_length=10, description="Código postal del negocio")
    location_city: Optional[str] = Field(default=None, max_length=100, description="Ciudad o municipio")
    notes: Optional[str] = Field(default=None, max_length=500, description="Notas comerciales o de entrega")


class B2BListingUpdateRequest(BaseModel):
    """Solicitud de modificación de una oferta mayorista existente."""
    wholesale_price_mxn: Optional[Decimal] = Field(default=None, gt=0, description="Nuevo precio mayorista en $ MXN")
    min_wholesale_quantity: Optional[Decimal] = Field(default=None, gt=0, description="Cantidad mínima de compra")
    available_b2b_stock: Optional[Decimal] = Field(default=None, ge=0, description="Stock disponible para mayoreo")
    location_postal_code: Optional[str] = Field(default=None, max_length=10)
    location_city: Optional[str] = Field(default=None, max_length=100)
    is_active: Optional[bool] = Field(default=None, description="Pausar o reactivar oferta")
    notes: Optional[str] = Field(default=None, max_length=500)


class B2BListingResponse(BaseModel):
    """Respuesta con los datos de una publicación mayorista B2B."""
    id: uuid.UUID = Field(description="ID de la publicación B2B")
    tenant_id: uuid.UUID = Field(description="ID del comercio vendedor")
    seller_store_name: str = Field(description="Nombre comercial de la tienda vendedora")
    product_id: uuid.UUID = Field(description="ID del producto base")
    product_name: str = Field(description="Nombre del producto")
    product_sku: str = Field(description="Código SKU")
    product_image_url: Optional[str] = Field(default=None, description="Fotografía del artículo")
    wholesale_price_mxn: Decimal = Field(description="Precio de mayoreo en $ MXN")
    regular_price_mxn: Optional[Decimal] = Field(default=None, description="Precio de venta al público de referencia")
    min_wholesale_quantity: Decimal = Field(description="Lote mínimo requerido")
    available_b2b_stock: Decimal = Field(description="Existencias disponibles para mayoreo")
    location_postal_code: Optional[str] = Field(default=None)
    location_city: Optional[str] = Field(default=None)
    is_active: bool = Field(description="Estado activo")
    notes: Optional[str] = Field(default=None)
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
