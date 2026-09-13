# Exportación de servicios del módulo Community B2B Catalog
from app.modules.community_catalog.services.b2b_marketplace_service import B2BMarketplaceService
from app.modules.community_catalog.services.b2b_order_service import B2BOrderService

__all__ = [
    "B2BMarketplaceService",
    "B2BOrderService",
]
