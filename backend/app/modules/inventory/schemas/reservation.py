# Importación del módulo datetime para marcas de tiempo
from datetime import datetime
# Importación del módulo decimal para precisión en cantidades
from decimal import Decimal
# Importación de tipado estático
from typing import Optional
# Importación de UUID para tipado de identificadores
import uuid
# Importación de BaseModel, ConfigDict y Field de Pydantic
from pydantic import BaseModel, ConfigDict, Field

# Importación del enum de estado de reservas
from app.modules.inventory.domain.stock_reservation import ReservationStatus


class StockReservationCreate(BaseModel):
    """
    Esquema de entrada para crear un apartado temporal de existencias (RF-06).
    """
    # Identificador del producto
    product_id: uuid.UUID = Field(..., description="UUID del producto a apartar")
    # Identificador del almacén
    warehouse_id: uuid.UUID = Field(..., description="UUID del almacén de resguardo")
    # Cantidad positiva a reservar
    quantity: Decimal = Field(
        ...,
        gt=0,
        description="Cantidad a apartar temporalmente",
        examples=[2.0, 1.0],
    )
    # Minutos de vigencia del apartado (por defecto 15 minutos según RF-06 / Const. Art. 7.1)
    ttl_minutes: int = Field(
        15,
        ge=1,
        le=60,
        description="Tiempo de vida en minutos antes de liberar automáticamente el stock",
    )
    # Identificador opcional de la venta o sesión en proceso
    reference_id: Optional[uuid.UUID] = Field(
        None,
        description="UUID de la venta en proceso o carrito",
    )


class StockReservationResponse(BaseModel):
    """
    Esquema de salida con el detalle de un apartado de stock con TTL.
    """
    id: uuid.UUID = Field(..., description="UUID único de la reserva")
    tenant_id: uuid.UUID = Field(..., description="UUID del comercio propietario")
    product_id: uuid.UUID = Field(..., description="UUID del producto")
    product_name: Optional[str] = Field(None, description="Nombre del producto apartado")
    warehouse_id: uuid.UUID = Field(..., description="UUID del almacén")
    quantity: Decimal = Field(..., description="Cantidad apartada")
    status: ReservationStatus = Field(..., description="Estado de vigencia (PENDING, COMMITTED, RELEASED, EXPIRED)")
    reference_id: Optional[uuid.UUID] = Field(None, description="ID de referencia externa")
    expires_at: datetime = Field(..., description="Estampa de tiempo límite de expiración")
    created_at: datetime = Field(..., description="Estampa de tiempo de emisión")

    model_config = ConfigDict(from_attributes=True)
