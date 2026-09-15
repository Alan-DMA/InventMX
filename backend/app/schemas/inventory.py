from pydantic import BaseModel, Field
from uuid import UUID
from decimal import Decimal
from typing import Optional, List
from datetime import datetime

# --- Categoría ---
class CategoryCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = None

class CategoryResponse(BaseModel):
    id: UUID
    tenant_id: UUID
    name: str
    description: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


# --- Producto ---
class ProductCreate(BaseModel):
    category_id: Optional[UUID] = None
    barcode: Optional[str] = None
    name: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    cost_usd: Decimal = Field(default=Decimal("0.00"), ge=0)
    price_usd: Decimal = Field(default=Decimal("0.00"), ge=0)
    price_ves_manual: Optional[Decimal] = Field(default=None, ge=0)
    stock_inicial: Decimal = Field(default=Decimal("0.00"), ge=0) # Usado para inicializar inventario en almacén principal

class ProductUpdate(BaseModel):
    category_id: Optional[UUID] = None
    barcode: Optional[str] = None
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    cost_usd: Optional[Decimal] = Field(None, ge=0)
    price_usd: Optional[Decimal] = Field(None, ge=0)
    price_ves_manual: Optional[Decimal] = Field(None, ge=0)
    is_active: Optional[bool] = None

class ProductResponse(BaseModel):
    id: UUID
    tenant_id: UUID
    category_id: Optional[UUID] = None
    barcode: Optional[str] = None
    name: str
    description: Optional[str] = None
    cost_usd: Decimal
    price_usd: Decimal
    price_ves_manual: Optional[Decimal] = None
    price_ves_calculated: Decimal  # Calculado dinámicamente usando la tasa del tenant si el manual es nulo
    is_active: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# --- Inventario ---
class InventoryResponse(BaseModel):
    id: UUID
    tenant_id: UUID
    product_id: UUID
    warehouse_id: UUID
    stock_available: Decimal
    stock_reserved: Decimal
    updated_at: datetime

    class Config:
        from_attributes = True

class InventoryReserve(BaseModel):
    product_id: UUID
    warehouse_id: UUID
    quantity: Decimal = Field(..., gt=0)
    sale_id: str

class InventoryRelease(BaseModel):
    product_id: UUID
    warehouse_id: UUID
    quantity: Decimal = Field(..., gt=0)
    sale_id: str


# --- Combo ---
class ComboItemCreate(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(..., gt=0)

class ComboItemResponse(BaseModel):
    product_id: UUID
    quantity: Decimal

    class Config:
        from_attributes = True

class ComboCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    price_usd: Decimal = Field(..., gt=0)
    items: List[ComboItemCreate] = Field(..., min_length=1)

class ComboResponse(BaseModel):
    id: UUID
    tenant_id: UUID
    name: str
    price_usd: Decimal
    is_active: bool
    created_at: datetime
    items: List[ComboItemResponse]

    class Config:
        from_attributes = True


# --- Almacenes y Operaciones de Inventario ---
class WarehouseResponse(BaseModel):
    id: UUID
    tenant_id: UUID
    name: str
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True


class InventoryAdjustRequest(BaseModel):
    product_id: UUID
    warehouse_id: Optional[UUID] = None
    quantity_change: Decimal
    reason: str = "Ajuste manual"


class InventoryTransferRequest(BaseModel):
    product_id: UUID
    origin_warehouse_id: UUID
    target_warehouse_id: UUID
    quantity: Decimal = Field(..., gt=0)
    notes: Optional[str] = "Traslado entre almacenes"


class InventoryLoadItem(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(..., gt=0)
    cost_usd: Optional[Decimal] = None




class InventoryLoadRequest(BaseModel):
    document_type: str = "NOTA_ENTREGA"  # NOTA_ENTREGA, FACTURA, MANUAL
    document_number: Optional[str] = None
    supplier_name: Optional[str] = None
    warehouse_id: Optional[UUID] = None
    items: List[InventoryLoadItem]
    notes: Optional[str] = None


# --- A-07: Kardex (movimientos de inventario) ---
class InventoryMovementResponse(BaseModel):
    """Respuesta de un movimiento del Kardex de inventario."""
    id: UUID
    tenant_id: UUID
    product_id: UUID
    warehouse_id: UUID
    quantity: Decimal
    type: str                            # ENTRADA, SALIDA, RESERVA, LIBERACION, AJUSTE, DEVOLUCION, TRASLADO
    reference_document: Optional[str] = None
    notes: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True
