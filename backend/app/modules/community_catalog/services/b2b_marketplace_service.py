# Importación de precisión decimal para Pesos Mexicanos
from datetime import datetime
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional, Tuple
# Importación de identificadores UUID
import uuid

# Importación de excepciones HTTP de FastAPI
from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de entidades de dominio
from app.modules.auth_tenancy.domain.user import User
from app.modules.community_catalog.domain.b2b_listing import B2BListing
from app.modules.community_catalog.repositories.b2b_marketplace_repository import B2BMarketplaceRepository
from app.modules.community_catalog.schemas.b2b_marketplace import (
    B2BListingCreateRequest,
    B2BListingResponse,
    B2BListingUpdateRequest,
)
from app.modules.inventory.domain.product import Product


class B2BMarketplaceService:
    """
    Servicio de Catálogo Comunitario B2B y Ofertas Mayoristas (RF-27 / Const. Art. 4.3).
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repo = B2BMarketplaceRepository(session)

    async def create_listing(
        self,
        request: B2BListingCreateRequest,
        current_user: User,
    ) -> B2BListingResponse:
        """Publica una nueva oferta mayorista para la red de comercios."""
        # 1. Validar que el producto pertenezca al comercio del usuario y esté activo
        stmt = select(Product).where(
            Product.id == request.product_id,
            Product.tenant_id == current_user.tenant_id,
            Product.is_active == True,
        )
        res = await self.session.execute(stmt)
        product = res.scalar_one_or_none()
        if not product:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="El producto no existe en su inventario o se encuentra inactivo.",
            )

        # 2. Instanciar la publicación B2B con snapshot de producto
        listing = B2BListing(
            tenant_id=current_user.tenant_id,
            product_id=product.id,
            product_name=product.name,
            product_sku=product.sku,
            product_image_url=product.image_url,
            wholesale_price_mxn=request.wholesale_price_mxn,
            regular_price_mxn=product.price_mxn,
            min_wholesale_quantity=request.min_wholesale_quantity,
            available_b2b_stock=request.available_b2b_stock,
            location_postal_code=request.location_postal_code,
            location_city=request.location_city,
            is_active=True,
            notes=request.notes,
        )
        created = await self.repo.create_listing(listing)

        return self._build_listing_response(
            created,
            product.name,
            product.sku,
            product.image_url,
            product.price_mxn,
            current_user.store_name if hasattr(current_user, 'store_name') else "Mi Tienda",
        )

    async def get_my_listings(
        self,
        current_user: User,
        is_active: Optional[bool] = None,
    ) -> List[B2BListingResponse]:
        """Consulta las publicaciones creadas por el comercio del usuario."""
        listings = await self.repo.get_my_listings(current_user.tenant_id, is_active)
        return [self._map_listing_to_response(l) for l in listings]

    async def search_marketplace(
        self,
        current_user: User,
        search: Optional[str] = None,
        city: Optional[str] = None,
        postal_code: Optional[str] = None,
        max_price: Optional[Decimal] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[B2BListingResponse], int]:
        """Explora ofertas mayoristas de otros comercios en la red comunitaria."""
        listings, total_count = await self.repo.search_marketplace(
            search=search,
            city=city,
            postal_code=postal_code,
            max_price=max_price,
            exclude_tenant_id=current_user.tenant_id,
            limit=limit,
            offset=offset,
        )
        return [self._map_listing_to_response(l) for l in listings], total_count

    async def update_listing(
        self,
        listing_id: uuid.UUID,
        request: B2BListingUpdateRequest,
        current_user: User,
    ) -> B2BListingResponse:
        """Modifica parámetros de una publicación B2B propia."""
        listing = await self.repo.get_listing_by_id(listing_id)
        if not listing or listing.tenant_id != current_user.tenant_id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Publicación mayorista no encontrada.",
            )

        update_data = request.model_dump(exclude_unset=True)
        updated = await self.repo.update_listing(listing, update_data)
        return self._map_listing_to_response(updated)

    def _map_listing_to_response(self, listing: B2BListing) -> B2BListingResponse:
        """Construye el DTO de respuesta a partir de la entidad B2BListing."""
        seller_name = listing.tenant.name if listing.tenant else "Comercio Asociado"

        return B2BListingResponse(
            id=listing.id,
            tenant_id=listing.tenant_id,
            seller_store_name=seller_name,
            product_id=listing.product_id,
            product_name=listing.product_name,
            product_sku=listing.product_sku or "",
            product_image_url=listing.product_image_url,
            wholesale_price_mxn=listing.wholesale_price_mxn,
            regular_price_mxn=listing.regular_price_mxn,
            min_wholesale_quantity=listing.min_wholesale_quantity,
            available_b2b_stock=listing.available_b2b_stock,
            location_postal_code=listing.location_postal_code,
            location_city=listing.location_city,
            is_active=listing.is_active,
            notes=listing.notes,
            created_at=listing.created_at,
        )

    def _build_listing_response(
        self,
        listing: B2BListing,
        product_name: str,
        product_sku: str,
        product_image_url: Optional[str],
        regular_price_mxn: Optional[Decimal],
        store_name: str,
    ) -> B2BListingResponse:
        return B2BListingResponse(
            id=listing.id,
            tenant_id=listing.tenant_id,
            seller_store_name=store_name,
            product_id=listing.product_id,
            product_name=product_name,
            product_sku=product_sku or "",
            product_image_url=product_image_url,
            wholesale_price_mxn=listing.wholesale_price_mxn,
            regular_price_mxn=regular_price_mxn,
            min_wholesale_quantity=listing.min_wholesale_quantity,
            available_b2b_stock=listing.available_b2b_stock,
            location_postal_code=listing.location_postal_code,
            location_city=listing.location_city,
            is_active=listing.is_active,
            notes=listing.notes,
            created_at=listing.created_at,
        )
