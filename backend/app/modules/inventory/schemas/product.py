# Importación del módulo datetime para marcas de tiempo
from datetime import datetime
# Importación del módulo decimal para precisión monetaria
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de UUID para claves primarias y foráneas
import uuid
# Importación de BaseModel, ConfigDict y Field de Pydantic
from pydantic import BaseModel, ConfigDict, Field, field_validator


class ProductStockResponse(BaseModel):
    """
    Esquema de existencias físicas desglosadas por almacén.
    """
    # Identificador del registro de stock
    id: uuid.UUID = Field(..., description="UUID del registro de existencias")
    # Identificador del almacén
    warehouse_id: uuid.UUID = Field(..., description="UUID del almacén")
    # Existencias físicas disponibles actualmente (Campo Vital 3)
    current_stock: Decimal = Field(..., ge=0, description="Existencias disponibles")
    # Stock reservado temporalmente para ventas en proceso
    reserved_stock: Decimal = Field(Decimal("0.00"), ge=0, description="Existencias apartadas")
    # Fecha de última mutación
    updated_at: datetime = Field(..., description="Estampa de tiempo de actualización")

    model_config = ConfigDict(from_attributes=True)


class ProductCreateVital(BaseModel):
    """
    Esquema de entrada para el Registro Minimalista de 3 Campos Vitales (SR-08 / Const. Art. 7.3).
    Permite registrar un producto en menos de 5 segundos requiriendo únicamente:
    1. name: Nombre comercial
    2. price_mxn: Precio de venta en MXN
    3. initial_stock: Existencias iniciales (por defecto 0.0)
    Los demás campos (SKU, categoría, almacén) se autogeneran si no son proporcionados.
    """
    # Campo Vital 1: Nombre comercial
    name: str = Field(
        ...,
        min_length=1,
        max_length=255,
        description="Nombre comercial del producto (Campo Vital 1)",
        examples=["Coca-Cola 600ml", "Sabritas Sal 45g", "Huevo Blanco 1kg"],
    )

    # Campo Vital 2: Precio de venta en Pesos Mexicanos
    price_mxn: Decimal = Field(
        ...,
        ge=0,
        description="Precio de venta en Pesos Mexicanos (Campo Vital 2)",
        examples=[18.50, 45.00, 120.00],
    )

    # Campo Vital 3: Existencias físicas iniciales
    initial_stock: Decimal = Field(
        Decimal("0.00"),
        ge=0,
        description="Cantidad inicial en inventario (Campo Vital 3)",
        examples=[24.0, 50.0, 10.0],
    )

    # Campos secundarios opcionales
    cost_mxn: Optional[Decimal] = Field(
        Decimal("0.00"),
        ge=0,
        description="Costo de compra en Pesos Mexicanos ($ MXN)",
        examples=[14.00, 32.00],
    )

    cost_usd_import: Optional[Decimal] = Field(
        None,
        ge=0,
        description="Costo de importación opcional en USD (RF-02)",
    )

    sku: Optional[str] = Field(
        None,
        max_length=50,
        description="SKU manual opcional (si se omite, se genera 'NEX-XXXXX')",
        examples=["NEX-10023", "PROD-AB-01"],
    )

    barcode: Optional[str] = Field(
        None,
        max_length=50,
        description="Código de barras físico EAN-13 o UPC",
        examples=["7501055300075"],
    )

    category_id: Optional[uuid.UUID] = Field(
        None,
        description="UUID de categoría (si se omite, se asigna 'General')",
    )

    warehouse_id: Optional[uuid.UUID] = Field(
        None,
        description="UUID de almacén destino (si se omite, se asigna el principal)",
    )

    min_stock_alert: Optional[Decimal] = Field(
        Decimal("5.00"),
        ge=0,
        description="Umbral de advertencia para stock bajo",
    )

    image_url: Optional[str] = Field(
        None,
        max_length=500,
        description="Enlace URL a la fotografía del producto",
    )

    @field_validator("name")
    @classmethod
    def validate_name_not_blank(cls, v: str) -> str:
        # Validación de que el nombre no contenga solo espacios en blanco
        cleaned = v.strip()
        if not cleaned:
            raise ValueError("El nombre del producto no puede estar vacío.")
        return cleaned


class ProductUpdate(BaseModel):
    """
    Esquema para la actualización parcial de un producto.
    """
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    price_mxn: Optional[Decimal] = Field(None, ge=0)
    cost_mxn: Optional[Decimal] = Field(None, ge=0)
    cost_usd_import: Optional[Decimal] = Field(None, ge=0)
    sku: Optional[str] = Field(None, max_length=50)
    barcode: Optional[str] = Field(None, max_length=50)
    category_id: Optional[uuid.UUID] = None
    min_stock_alert: Optional[Decimal] = Field(None, ge=0)
    image_url: Optional[str] = Field(None, max_length=500)
    is_active: Optional[bool] = None


class ProductResponse(BaseModel):
    """
    Esquema de salida completo para el detalle de un Producto.
    """
    id: uuid.UUID = Field(..., description="UUID único del producto")
    tenant_id: uuid.UUID = Field(..., description="UUID del comercio propietario")
    category_id: Optional[uuid.UUID] = Field(None, description="UUID de la categoría asignada")
    name: str = Field(..., description="Nombre comercial del producto")
    price_mxn: Decimal = Field(..., description="Precio de venta en Pesos Mexicanos")
    cost_mxn: Decimal = Field(..., description="Costo de compra en Pesos Mexicanos")
    cost_usd_import: Optional[Decimal] = Field(None, description="Costo de importación en USD")
    sku: str = Field(..., description="Código de identificación SKU")
    barcode: Optional[str] = Field(None, description="Código de barras EAN/UPC")
    min_stock_alert: Decimal = Field(..., description="Umbral para alerta de stock bajo")
    image_url: Optional[str] = Field(None, description="URL de la fotografía del producto")
    is_active: bool = Field(..., description="Estado de disponibilidad para venta")
    created_at: datetime = Field(..., description="Estampa de tiempo de creación")
    updated_at: datetime = Field(..., description="Estampa de tiempo de actualización")

    # Campos calculados y enriquecidos
    total_stock: Decimal = Field(Decimal("0.00"), description="Suma total de existencias en todos los almacenes")
    is_low_stock: bool = Field(False, description="Determina si el producto está en nivel crítico")
    margin_percentage: Optional[Decimal] = Field(None, description="Porcentaje de margen de ganancia bruto")
    category_name: Optional[str] = Field(None, description="Nombre de la categoría asociada")
    stocks: List[ProductStockResponse] = Field(default_factory=list, description="Desglose de existencias por almacén")

    model_config = ConfigDict(from_attributes=True)


class ProductListItem(BaseModel):
    """
    Esquema ligero y optimizado para el listado del catálogo y la pantalla del POS.
    """
    id: uuid.UUID
    name: str
    price_mxn: Decimal
    cost_mxn: Decimal
    sku: str
    barcode: Optional[str] = None
    total_stock: Decimal = Decimal("0.00")
    is_low_stock: bool = False
    category_id: Optional[uuid.UUID] = None
    category_name: Optional[str] = None
    image_url: Optional[str] = None
    is_active: bool = True

    model_config = ConfigDict(from_attributes=True)
