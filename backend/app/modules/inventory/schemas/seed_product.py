# Importación del módulo decimal para precios en MXN
from decimal import Decimal
# Importación de tipado estático
from typing import Optional
# Importación de UUID para identificación
import uuid
# Importación de BaseModel, ConfigDict y Field de Pydantic
from pydantic import BaseModel, ConfigDict, Field


class SeedProductResponse(BaseModel):
    """
    Esquema de salida para un producto del Catálogo Semilla Maestro EAN-13 México (Tier 1).
    """
    # Identificador único del producto semilla
    id: uuid.UUID = Field(..., description="UUID del producto en catálogo semilla")
    # Código de barras oficial EAN-13
    barcode: str = Field(..., description="Código de barras oficial GS1 México", examples=["7501055300075"])
    # Nombre comercial oficial
    name: str = Field(..., description="Nombre comercial oficial", examples=["Coca-Cola Original 600ml NR"])
    # Marca o fabricante
    brand: Optional[str] = Field(None, description="Marca comercial del producto", examples=["Coca-Cola"])
    # Categoría sugerida
    category_name: str = Field("General", description="Categoría de clasificación sugerida", examples=["Bebidas"])
    # Precio de venta sugerido al público en Pesos Mexicanos
    suggested_price_mxn: Decimal = Field(
        Decimal("0.00"),
        description="Precio de venta sugerido en Pesos Mexicanos ($ MXN)",
        examples=[18.50],
    )
    # URL de imagen oficial
    image_url: Optional[str] = Field(None, description="Fotografía oficial de referencia")
    # Indicador de verificación oficial GS1
    is_verified: bool = Field(True, description="Indica si los datos fueron validados con catálogo maestro")

    model_config = ConfigDict(from_attributes=True)


class EanLookupResponse(BaseModel):
    """
    Respuesta enriquecida para el escáner de códigos de barras (RF-29 / Const. Art. 7.5).
    Permite autocompletar la ficha de producto en < 5ms si existe en el catálogo semilla.
    """
    # Bandera de coincidencia
    found: bool = Field(..., description="Indica si el código fue encontrado en el catálogo semilla")
    # Datos oficiales del producto (None si found es False)
    product: Optional[SeedProductResponse] = Field(
        None,
        description="Ficha técnica oficial para autocompletar nombre, marca y categoría",
    )
