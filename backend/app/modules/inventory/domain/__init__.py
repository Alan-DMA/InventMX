# Exportación centralizada de modelos de dominio del módulo de inventario
from app.modules.inventory.domain.category import Category
from app.modules.inventory.domain.product import Product
from app.modules.inventory.domain.product_stock import ProductStock
from app.modules.inventory.domain.warehouse import Warehouse

__all__ = [
    "Category",
    "Warehouse",
    "Product",
    "ProductStock",
]
