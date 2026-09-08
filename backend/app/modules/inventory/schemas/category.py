# Importación del módulo datetime para marcas de tiempo en respuestas
from datetime import datetime
# Importación de tipado estático
from typing import Optional
# Importación de UUID para tipado estricto
import uuid
# Importación de BaseModel y Field de Pydantic
from pydantic import BaseModel, ConfigDict, Field


class CategoryBase(BaseModel):
    """
    Esquema base con los atributos comunes de una Categoría.
    """
    # Nombre de la categoría
    name: str = Field(
        ...,
        min_length=1,
        max_length=100,
        description="Nombre descriptivo de la categoría de productos",
        examples=["Abarrotes", "Bebidas y Refrescos", "Lácteos"],
    )
    # Descripción opcional
    description: Optional[str] = Field(
        None,
        description="Detalle o notas adicionales sobre la clasificación",
        examples=["Productos de canasta básica y despensa general"],
    )


class CategoryCreate(CategoryBase):
    """
    Esquema de entrada para la creación de una nueva Categoría.
    """
    pass


class CategoryUpdate(BaseModel):
    """
    Esquema de entrada para la actualización parcial de una Categoría.
    """
    name: Optional[str] = Field(
        None,
        min_length=1,
        max_length=100,
        description="Nuevo nombre para la categoría",
    )
    description: Optional[str] = Field(
        None,
        description="Nueva descripción para la categoría",
    )


class CategoryResponse(CategoryBase):
    """
    Esquema de salida para la exposición pública de una Categoría.
    """
    # Identificador único de la categoría
    id: uuid.UUID = Field(..., description="UUID único de la categoría")
    # Identificador del comercio propietario
    tenant_id: uuid.UUID = Field(..., description="UUID del comercio dueño")
    # Fecha de registro
    created_at: datetime = Field(..., description="Estampa de tiempo de creación")

    # Configuración para lectura directa desde modelos ORM de SQLAlchemy
    model_config = ConfigDict(from_attributes=True)
