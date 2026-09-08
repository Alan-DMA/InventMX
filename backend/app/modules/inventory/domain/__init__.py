# Exportación centralizada de modelos de dominio del módulo de inventario
from app.modules.inventory.domain.category import Category
from app.modules.inventory.domain.combo import Combo, ComboItem
from app.modules.inventory.domain.inventory_movement import (
    InventoryMovement,
    MovementType,
)
from app.modules.inventory.domain.product import Product
from app.modules.inventory.domain.product_stock import ProductStock
from app.modules.inventory.domain.seed_product import SeedProduct
from app.modules.inventory.domain.stock_reservation import (
    ReservationStatus,
    StockReservation,
)
from app.modules.inventory.domain.warehouse import Warehouse

__all__ = [
    "Category",
    "Warehouse",
    "Product",
    "ProductStock",
    "Combo",
    "ComboItem",
    "InventoryMovement",
    "MovementType",
    "StockReservation",
    "ReservationStatus",
    "SeedProduct",
]
