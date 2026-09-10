# Importación de precisión decimal para Pesos Mexicanos
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field


class ReceiptOcrParseRequest(BaseModel):
    """
    Contrato de solicitud para procesar texto extraído por OCR On-Device (RF-28).
    """
    raw_text: str = Field(
        min_length=3,
        description="Texto plano extraído por Google ML Kit en el dispositivo cliente",
    )
    supplier_id: Optional[uuid.UUID] = Field(
        default=None,
        description="ID opcional del proveedor emisor de la factura",
    )
    image_url: Optional[str] = Field(
        default=None,
        max_length=500,
        description="Enlace opcional a la fotografía de la factura",
    )


class ReceiptOcrItemResponse(BaseModel):
    """
    Renglón estructurado de producto extraído de una factura/remisión física.
    """
    raw_line: str = Field(description="Línea original detectada por el motor OCR")
    detected_name: str = Field(description="Nombre o descripción comercial del producto")
    detected_quantity: Decimal = Field(
        default=Decimal("1.0000"),
        description="Cantidad física de piezas o kilogramos detectada",
    )
    detected_unit_cost_mxn: Decimal = Field(
        default=Decimal("0.0000"),
        description="Costo unitario detectado en Pesos Mexicanos ($ MXN)",
    )
    detected_total_mxn: Decimal = Field(
        default=Decimal("0.00"),
        description="Importe total de la línea en $ MXN",
    )
    matched_product_id: Optional[uuid.UUID] = Field(
        default=None,
        description="ID del producto emparejado en el catálogo del comercio (si existe)",
    )
    matched_product_name: Optional[str] = Field(
        default=None,
        description="Nombre del producto coincidente en inventario",
    )
    matched_product_sku: Optional[str] = Field(
        default=None,
        description="SKU del producto coincidente",
    )
    confidence_score: float = Field(
        default=1.0,
        ge=0.0,
        le=1.0,
        description="Nivel de confianza en la extracción y emparejamiento (0.0 a 1.0)",
    )


class ReceiptOcrParseResponse(BaseModel):
    """
    Respuesta consolidada con la estructura normalizada de la factura física.
    """
    supplier_name: Optional[str] = Field(default=None, description="Nombre de la distribuidora detectada")
    invoice_reference: Optional[str] = Field(default=None, description="Folio o número de remisión/factura")
    items: List[ReceiptOcrItemResponse] = Field(
        default_factory=list,
        description="Lista de productos y cantidades detectadas",
    )
    total_amount_mxn: Decimal = Field(
        default=Decimal("0.00"),
        description="Suma total de la factura en Pesos Mexicanos ($ MXN)",
    )
    unmatched_items_count: int = Field(
        default=0,
        description="Cantidad de productos que aún no existen en el catálogo y requieren alta rápida",
    )


class VoiceDictationParseRequest(BaseModel):
    """
    Contrato de solicitud para interpretar dictado por voz nativo en español mexicano (SR-09).
    """
    voice_text: str = Field(
        min_length=2,
        description="Texto transcrito por el motor nativo de reconocimiento de voz",
    )


class VoiceDictationParseResponse(BaseModel):
    """
    Resultado estructurado de los 3 Campos Vitales a partir del dictado de voz.
    """
    name: str = Field(description="Nombre comercial interpretado (Campo Vital 1)")
    price_mxn: Decimal = Field(description="Precio de venta en $ MXN (Campo Vital 2)")
    cost_mxn: Optional[Decimal] = Field(
        default=None,
        description="Costo de compra en $ MXN (opcional)",
    )
    initial_stock: Decimal = Field(
        default=Decimal("0.00"),
        description="Existencias iniciales (Campo Vital 3)",
    )
    confidence: float = Field(
        default=1.0,
        ge=0.0,
        le=1.0,
        description="Nivel de confianza de la interpretación acústica/semántica",
    )
