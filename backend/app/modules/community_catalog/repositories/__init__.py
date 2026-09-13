# Exportación de repositorios del módulo Community B2B Catalog
from app.modules.community_catalog.repositories.b2b_marketplace_repository import B2BMarketplaceRepository
from app.modules.community_catalog.repositories.b2b_order_repository import B2BOrderRepository

__all__ = [
    "B2BMarketplaceRepository",
    "B2BOrderRepository",
]
