# Exportación centralizada de repositorios del módulo de inventario
from app.modules.inventory.repositories.category_repository import CategoryRepository
from app.modules.inventory.repositories.combo_repository import ComboRepository
from app.modules.inventory.repositories.movement_repository import MovementRepository
from app.modules.inventory.repositories.product_repository import ProductRepository
from app.modules.inventory.repositories.reservation_repository import (
    ReservationRepository,
)
from app.modules.inventory.repositories.warehouse_repository import WarehouseRepository

__all__ = [
    "CategoryRepository",
    "WarehouseRepository",
    "ProductRepository",
    "ComboRepository",
    "MovementRepository",
    "ReservationRepository",
]
