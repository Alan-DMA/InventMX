# Exportación centralizada de repositorios del módulo de inventario
from app.modules.inventory.repositories.category_repository import CategoryRepository
from app.modules.inventory.repositories.product_repository import ProductRepository
from app.modules.inventory.repositories.warehouse_repository import WarehouseRepository

__all__ = [
    "CategoryRepository",
    "WarehouseRepository",
    "ProductRepository",
]
