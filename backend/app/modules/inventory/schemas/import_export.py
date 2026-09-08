# Importación de tipado estático
from typing import Any, Dict, List, Optional
# Importación de BaseModel, ConfigDict y Field de Pydantic
from pydantic import BaseModel, ConfigDict, Field


class ColumnMapping(BaseModel):
    """
    Esquema para definir el mapeo dinámico entre las columnas del archivo Excel/CSV
    del comerciante y los campos del sistema (RF-01).
    Permite importar archivos sin imponer una plantilla rígida.
    """
    # Columna obligatoria para Nombre del producto (Campo Vital 1)
    name_column: str = Field(
        ...,
        description="Nombre o encabezado de la columna que contiene el Nombre del producto",
        examples=["DESCRIPCION", "Nombre", "Artículo"],
    )
    # Columna obligatoria para Precio de venta en MXN (Campo Vital 2)
    price_column: str = Field(
        ...,
        description="Nombre o encabezado de la columna con el Precio de venta en $ MXN",
        examples=["PRECIO_PUBLICO", "Precio", "Venta"],
    )
    # Columna obligatoria para Existencias iniciales (Campo Vital 3)
    stock_column: str = Field(
        ...,
        description="Nombre o encabezado de la columna con las Existencias iniciales",
        examples=["EXISTENCIAS", "Stock", "Cantidad"],
    )
    # Columna opcional para Costo de compra en MXN
    cost_column: Optional[str] = Field(
        None,
        description="Columna con el Costo de adquisición unitario en $ MXN",
        examples=["COSTO", "Precio_Compra"],
    )
    # Columna opcional para Código de barras físico EAN
    barcode_column: Optional[str] = Field(
        None,
        description="Columna con el Código de barras físico",
        examples=["CODIGO_BARRAS", "EAN", "Barcode"],
    )
    # Columna opcional para Categoría de clasificación
    category_column: Optional[str] = Field(
        None,
        description="Columna con el Nombre de la categoría",
        examples=["CATEGORIA", "Familia", "Departamento"],
    )
    # Columna opcional para Código SKU personalizado
    sku_column: Optional[str] = Field(
        None,
        description="Columna con el Código SKU propio (si se omite, se autogenera NEX-XXXXX)",
        examples=["SKU", "Codigo_Interno"],
    )


class ImportPreviewResponse(BaseModel):
    """
    Esquema de respuesta para la previsualización de un archivo Excel/CSV cargado (RF-01).
    Muestra los encabezados detectados y las primeras filas para que el usuario configure el mapeo.
    """
    # Nombre original del archivo subido
    filename: str = Field(..., description="Nombre del archivo analizado")
    # Lista de encabezados detectados en la primera fila
    headers: List[str] = Field(..., description="Lista de encabezados de columnas encontrados")
    # Primeras 5 filas de muestra como diccionarios {encabezado: valor}
    sample_rows: List[Dict[str, Any]] = Field(..., description="Primeras filas de muestra para previsualización")
    # Estimación de filas totales con datos
    total_detected_rows: int = Field(..., description="Total estimado de filas en la hoja")
    # Mapeo sugerido por heurística básica de nombres de columnas
    suggested_mapping: Optional[Dict[str, str]] = Field(None, description="Sugerencia automática de mapeo de columnas")


class ImportRowError(BaseModel):
    """
    Detalle de error no fatal en una fila específica durante la importación masiva.
    """
    # Número de fila física en la hoja (1-indexed)
    row_number: int = Field(..., description="Número de fila donde ocurrió el problema")
    # Causa o motivo del error de procesamiento
    reason: str = Field(..., description="Descripción del error de validación o datos incompletos")


class ImportExecutionResponse(BaseModel):
    """
    Esquema de respuesta consolidada tras ejecutar la importación masiva en base de datos.
    """
    # Total de filas leídas en el archivo
    total_rows: int = Field(..., description="Total de filas leídas en el archivo")
    # Cantidad de productos dados de alta con éxito
    imported_count: int = Field(..., description="Total de productos registrados exitosamente")
    # Cantidad de filas omitidas (vacías o inválidas)
    skipped_count: int = Field(..., description="Total de filas omitidas o con error")
    # Lista de errores detallados recolectados por fila
    errors: List[ImportRowError] = Field(default_factory=list, description="Desglose de errores no fatales")
    # Estado general de la operación
    status: str = Field("completed", description="Estado final de la importación (completed, partial)")
