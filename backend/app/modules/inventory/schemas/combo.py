# Importación del módulo datetime para marcas de tiempo
from datetime import datetime
# Importación del módulo decimal para cálculo monetario
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de UUID para tipado de identificadores
import uuid
# Importación de BaseModel, ConfigDict y Field de Pydantic
from pydantic import BaseModel, ConfigDict, Field, field_validator


class ComboItemCreate(BaseModel):
    """
    Esquema de entrada para agregar un producto a un Combo.
    """
    # Identificador del producto componente
    product_id: uuid.UUID = Field(..., description="UUID del producto individual")
    # Cantidad requerida de este producto
    quantity: Decimal = Field(
        ...,
        gt=0,
        description="Cantidad requerida para conformar 1 combo",
        examples=[2.0, 1.0],
    )


class ComboItemResponse(BaseModel):
    """
    Esquema de salida con el desglose de un producto componente en un Combo.
    """
    id: uuid.UUID = Field(..., description="UUID del ítem de combo")
    product_id: uuid.UUID = Field(..., description="UUID del producto")
    product_name: str = Field(..., description="Nombre comercial del producto")
    quantity: Decimal = Field(..., description="Cantidad requerida")
    product_price_mxn: Decimal = Field(..., description="Precio individual en MXN")

    model_config = ConfigDict(from_attributes=True)


class ComboCreate(BaseModel):
    """
    Esquema de entrada para la creación de un nuevo Combo / Promoción (RF-03).
    """
    # Nombre de la promoción
    name: str = Field(
        ...,
        min_length=1,
        max_length=255,
        description="Nombre comercial de la promoción",
        examples=["Combo Fiesta: 2 Refrescos 600ml + 1 Papas 45g"],
    )
    # Descripción opcional
    description: Optional[str] = Field(
        None,
        description="Detalle o condiciones de la oferta",
    )
    # Precio único de venta en MXN
    price_mxn: Decimal = Field(
        ...,
        ge=0,
        description="Precio de venta consolidado del combo en Pesos Mexicanos ($ MXN)",
        examples=[45.00, 89.00],
    )
    # SKU opcional (si se omite, se autogenera 'NEX-XXXXX')
    sku: Optional[str] = Field(
        None,
        max_length=50,
        description="Código SKU opcional para la promoción",
    )
    # Código de barras opcional
    barcode: Optional[str] = Field(
        None,
        max_length=50,
        description="Código de barras EAN/UPC para escaneo en caja",
    )
    # URL de imagen
    image_url: Optional[str] = Field(
        None,
        max_length=500,
        description="Enlace a la fotografía del combo",
    )
    # Lista de artículos componentes (mínimo 2 artículos)
    items: List[ComboItemCreate] = Field(
        ...,
        min_length=2,
        description="Listado de al menos 2 productos que integran la promoción",
    )

    @field_validator("items")
    @classmethod
    def validate_unique_products(cls, v: List[ComboItemCreate]) -> List[ComboItemCreate]:
        # Validar que no se repita el mismo product_id en la lista
        product_ids = [item.product_id for item in v]
        if len(product_ids) != len(set(product_ids)):
            raise ValueError("No se puede incluir el mismo producto más de una vez en la lista de componentes.")
        return v


class ComboUpdate(BaseModel):
    """
    Esquema para la modificación parcial de un combo.
    """
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = Field(None)
    price_mxn: Optional[Decimal] = Field(None, ge=0)
    sku: Optional[str] = Field(None, max_length=50)
    barcode: Optional[str] = Field(None, max_length=50)
    image_url: Optional[str] = Field(None, max_length=500)
    is_active: Optional[bool] = None
    items: Optional[List[ComboItemCreate]] = Field(None, min_length=2)


class ComboResponse(BaseModel):
    """
    Esquema de salida completo para el detalle de un Combo.
    """
    id: uuid.UUID = Field(..., description="UUID único del combo")
    tenant_id: uuid.UUID = Field(..., description="UUID del comercio propietario")
    name: str = Field(..., description="Nombre comercial del combo")
    description: Optional[str] = Field(None, description="Descripción del combo")
    price_mxn: Decimal = Field(..., description="Precio de venta consolidado en MXN")
    sku: str = Field(..., description="Código SKU de la promoción")
    barcode: Optional[str] = Field(None, description="Código de barras escaneable")
    image_url: Optional[str] = Field(None, description="URL de la imagen del combo")
    is_active: bool = Field(..., description="Estado de disponibilidad para venta")
    available_combos: Decimal = Field(Decimal("0.00"), description="Combos máximos disponibles para armar según existencias")
    items: List[ComboItemResponse] = Field(default_factory=list, description="Desglose de productos componentes")
    created_at: datetime = Field(..., description="Estampa de tiempo de creación")
    updated_at: datetime = Field(..., description="Estampa de tiempo de actualización")

    model_config = ConfigDict(from_attributes=True)
