# Exportación centralizada de esquemas Pydantic del módulo de inventario
from app.modules.inventory.schemas.category import (
    CategoryCreate,
    CategoryResponse,
    CategoryUpdate,
)
from app.modules.inventory.schemas.product import (
    ProductCreateVital,
    ProductListItem,
    ProductResponse,
    ProductStockResponse,
    ProductUpdate,
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
]
