# Importación del módulo datetime para marcas de tiempo
from datetime import datetime
# Importación del módulo decimal para precisión en existencias
from decimal import Decimal
# Importación de tipado estático
from typing import Optional
# Importación de UUID para claves
import uuid
# Importación de BaseModel, ConfigDict y Field de Pydantic
from pydantic import BaseModel, ConfigDict, Field, field_validator

# Importación del enum de tipos de movimiento
from app.modules.inventory.domain.inventory_movement import MovementType


class StockAdjustmentCreate(BaseModel):
    """
    Esquema de entrada para registrar un ajuste físico manual de existencias (RF-05 / Const. Art. 7.1).
    Permite sumar existencias (+ Entrada) o restar existencias (- Salida / Merma).
    """
    # Identificador del producto
    product_id: uuid.UUID = Field(..., description="UUID del producto a ajustar")
    # Identificador del almacén donde ocurre el ajuste
    warehouse_id: uuid.UUID = Field(..., description="UUID del almacén donde reside el stock")
    # Cantidad a ajustar (positiva para entrada, negativa para salida o merma)
    quantity: Decimal = Field(
        ...,
        description="Cantidad a sumar (positiva) o restar (negativa)",
        examples=[10.0, -2.0],
    )
    # Clasificación específica del ajuste
    movement_type: Optional[MovementType] = Field(
        None,
        description="Tipo específico de ajuste (ADJUSTMENT_IN, ADJUSTMENT_OUT, WASTE_MERMA)",
    )
    # Costo unitario en MXN (opcional, para revalorización de compras o sobrantes)
    unit_cost_mxn: Optional[Decimal] = Field(
        None,
        ge=0,
        description="Costo unitario en Pesos Mexicanos ($ MXN)",
    )
    # Motivo, justificación o notas del ajuste
    notes: Optional[str] = Field(
        None,
        description="Justificación operativa del ajuste (ej. 'Conteo físico mensual', 'Merma por caducidad')",
        examples=["Conteo físico mensual", "Botella rota en anaquel"],
    )

    @field_validator("quantity")
    @classmethod
    def validate_quantity_not_zero(cls, v: Decimal) -> Decimal:
        if v == Decimal("0.00"):
            raise ValueError("La cantidad a ajustar no puede ser exactamente cero.")
        return v


class StockTransferCreate(BaseModel):
    """
    Esquema de entrada para realizar un traslado atómico de existencias entre dos almacenes (RF-07).
    """
    # Identificador del producto a trasladar
    product_id: uuid.UUID = Field(..., description="UUID del producto a transferir")
    # Identificador del almacén de origen
    from_warehouse_id: uuid.UUID = Field(..., description="UUID del almacén origen")
    # Identificador del almacén de destino
    to_warehouse_id: uuid.UUID = Field(..., description="UUID del almacén destino")
    # Cantidad positiva a trasladar
    quantity: Decimal = Field(
        ...,
        gt=0,
        description="Cantidad física a trasladar entre almacenes",
        examples=[12.0, 5.0],
    )
    # Notas u observaciones del traslado
    notes: Optional[str] = Field(
        None,
        description="Motivo del traslado (ej. 'Reabastecimiento de mostrador desde bodega')",
    )

    @field_validator("to_warehouse_id")
    @classmethod
    def validate_different_warehouses(cls, v: uuid.UUID, info) -> uuid.UUID:
        from_id = info.data.get("from_warehouse_id")
        if from_id and v == from_id:
            raise ValueError("El almacén de destino no puede ser igual al almacén de origen.")
        return v


class InventoryMovementResponse(BaseModel):
    """
    Esquema de salida con el detalle de un asiento contable en el Kardex inmutable.
    """
    id: uuid.UUID = Field(..., description="UUID único del movimiento en Kardex")
    tenant_id: uuid.UUID = Field(..., description="UUID del comercio propietario")
    product_id: uuid.UUID = Field(..., description="UUID del producto")
    product_name: Optional[str] = Field(None, description="Nombre del producto al momento del asiento")
    warehouse_id: uuid.UUID = Field(..., description="UUID del almacén afectado")
    warehouse_name: Optional[str] = Field(None, description="Nombre del almacén")
    from_warehouse_id: Optional[uuid.UUID] = Field(None, description="Almacén de origen (si aplica)")
    to_warehouse_id: Optional[uuid.UUID] = Field(None, description="Almacén de destino (si aplica)")
    user_id: Optional[uuid.UUID] = Field(None, description="Usuario responsable")
    movement_type: MovementType = Field(..., description="Tipo de movimiento registrado")
    quantity: Decimal = Field(..., description="Cantidad física movida")
    previous_stock: Decimal = Field(..., description="Saldo de existencias previo")
    new_stock: Decimal = Field(..., description="Saldo de existencias resultante")
    unit_cost_mxn: Decimal = Field(..., description="Costo unitario en Pesos Mexicanos")
    reference_id: Optional[uuid.UUID] = Field(None, description="ID de transacción asociada")
    notes: Optional[str] = Field(None, description="Observaciones del asiento")
    created_at: datetime = Field(..., description="Estampa de tiempo del asiento")

    model_config = ConfigDict(from_attributes=True)
