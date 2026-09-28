# Importación del módulo datetime para marcas de tiempo
from datetime import datetime
# Importación de tipado estático
from typing import Optional
# Importación de UUID para identificadores
import uuid
# Importación de BaseModel, ConfigDict y Field de Pydantic
from pydantic import BaseModel, ConfigDict, Field


class WarehouseBase(BaseModel):
    """
    Esquema base con los atributos fundamentales de un Almacén.
    """
    # Nombre de la ubicación física
    name: str = Field(
        ...,
        min_length=1,
        max_length=150,
        description="Nombre descriptivo del almacén o sucursal",
        examples=["Almacén Principal", "Bodega Tienda", "Sucursal Centro"],
    )
    # Indicador de almacén por defecto
    is_default: bool = Field(
        True,
        description="Indica si es la ubicación por defecto para recepciones y ventas",
    )


class WarehouseCreate(WarehouseBase):
    """
    Esquema de entrada para el registro de un nuevo almacén.
    """
    pass


class WarehouseUpdate(BaseModel):
    """
    Esquema para renombrar un almacén. El principal se cambia con
    `POST /inventory/warehouses/{id}/make-default` y la baja con `DELETE` (D7).
    """
    name: str = Field(
        ...,
        min_length=1,
        max_length=150,
        description="Nuevo nombre para el almacén (único en el comercio)",
    )


class WarehouseResponse(WarehouseBase):
    """
    Esquema de salida con el detalle de un Almacén.
    """
    # Identificador único UUID
    id: uuid.UUID = Field(..., description="UUID único del almacén")
    # Identificador del comercio propietario
    tenant_id: uuid.UUID = Field(..., description="UUID del comercio dueño")
    # Baja lógica (D7): los selectores sólo ofrecen los activos
    is_active: bool = Field(True, description="Falso si el almacén fue dado de baja")
    # Fecha de creación
    created_at: datetime = Field(..., description="Estampa de tiempo de registro")

    # Mapeo ORM automático
    model_config = ConfigDict(from_attributes=True)
