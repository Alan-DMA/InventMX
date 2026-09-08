# Exportación centralizada de esquemas Pydantic del módulo de inventario
from app.modules.inventory.schemas.category import (
    CategoryCreate,
    CategoryResponse,
    CategoryUpdate,
)
from app.modules.inventory.schemas.combo import (
    ComboCreate,
    ComboItemCreate,
    ComboItemResponse,
    ComboResponse,
    ComboUpdate,
)
from app.modules.inventory.schemas.movement import (
    InventoryMovementResponse,
    StockAdjustmentCreate,
    StockTransferCreate,
)
from app.modules.inventory.schemas.product import (
    ProductCreateVital,
    ProductListItem,
    ProductResponse,
    ProductStockResponse,
    ProductUpdate,
)
from app.modules.inventory.schemas.reservation import (
    StockReservationCreate,
    StockReservationResponse,
)
from app.modules.inventory.schemas.import_export import (
    ColumnMapping,
    ImportExecutionResponse,
    ImportPreviewResponse,
    ImportRowError,
)
from app.modules.inventory.schemas.seed_product import (
    EanLookupResponse,
    SeedProductResponse,
)
from app.modules.inventory.schemas.warehouse import (
    WarehouseCreate,
    WarehouseResponse,
    WarehouseUpdate,
)

__all__ = [
    "CategoryCreate",
    "CategoryUpdate",
    "CategoryResponse",
    "WarehouseCreate",
    "WarehouseUpdate",
    "WarehouseResponse",
    "ProductCreateVital",
    "ProductUpdate",
    "ProductResponse",
    "ProductListItem",
    "ProductStockResponse",
    "ComboCreate",
    "ComboUpdate",
    "ComboResponse",
    "ComboItemCreate",
    "ComboItemResponse",
    "StockAdjustmentCreate",
    "StockTransferCreate",
    "InventoryMovementResponse",
    "StockReservationCreate",
    "StockReservationResponse",
    "SeedProductResponse",
    "EanLookupResponse",
    "ColumnMapping",
    "ImportPreviewResponse",
    "ImportExecutionResponse",
    "ImportRowError",
]
