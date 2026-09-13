# Importación de precisión decimal para Pesos Mexicanos
from datetime import datetime
from decimal import Decimal
# Importación de tipado estático
from typing import Any, Dict, List, Optional, Tuple
# Importación de identificadores UUID
import uuid

# Importación de constructs de SQLAlchemy
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de entidades de dominio
from app.modules.community_catalog.domain.b2b_listing import B2BListing


class B2BMarketplaceRepository:
    """
    Repositorio de acceso a datos para publicaciones mayoristas B2B (RF-27).
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create_listing(self, listing: B2BListing) -> B2BListing:
        """Persiste una nueva publicación mayorista en la base de datos."""
        self.session.add(listing)
        await self.session.flush()
        await self.session.refresh(listing)
        return listing

    async def get_listing_by_id(self, listing_id: uuid.UUID) -> Optional[B2BListing]:
        """Consulta una publicación B2B por su ID único."""
        stmt = select(B2BListing).where(B2BListing.id == listing_id)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_my_listings(
        self,
        tenant_id: uuid.UUID,
        is_active: Optional[bool] = None,
    ) -> List[B2BListing]:
        """Obtiene las publicaciones B2B creadas por el comercio actual."""
        stmt = select(B2BListing).where(B2BListing.tenant_id == tenant_id)
        if is_active is not None:
            stmt = stmt.where(B2BListing.is_active == is_active)
        stmt = stmt.order_by(B2BListing.created_at.desc())
        result = await self.session.execute(stmt)
        return list(result.scalars().unique().all())

    async def search_marketplace(
        self,
        search: Optional[str] = None,
        city: Optional[str] = None,
        postal_code: Optional[str] = None,
        max_price: Optional[Decimal] = None,
        exclude_tenant_id: Optional[uuid.UUID] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[B2BListing], int]:
        """
        Búsqueda federada de ofertas mayoristas comunitarias con filtros por ubicación y precio.
        Retorna (lista_de_publicaciones, total_coincidencias).
        """
        base_query = (
            select(B2BListing)
            .where(
                B2BListing.is_active == True,
                B2BListing.available_b2b_stock > 0,
            )
        )

        # Excluir ofertas del propio comercio comprador
        if exclude_tenant_id:
            base_query = base_query.where(B2BListing.tenant_id != exclude_tenant_id)

        # Filtro de búsqueda textual en nombre de producto o SKU
        if search:
            search_pat = f"%{search.strip().lower()}%"
            base_query = base_query.where(
                or_(
                    func.lower(B2BListing.product_name).ilike(search_pat),
                    func.lower(B2BListing.product_sku).ilike(search_pat),
                )
            )

        # Filtro por ciudad
        if city:
            base_query = base_query.where(func.lower(B2BListing.location_city).ilike(f"%{city.strip().lower()}%"))

        # Filtro por código postal
        if postal_code:
            base_query = base_query.where(B2BListing.location_postal_code == postal_code.strip())

        # Filtro por precio tope en MXN
        if max_price:
            base_query = base_query.where(B2BListing.wholesale_price_mxn <= max_price)

        # Conteo total
        count_stmt = select(func.count()).select_from(base_query.subquery())
        total_count = (await self.session.execute(count_stmt)).scalar() or 0

        # Paginación y ordenamiento
        stmt = base_query.order_by(B2BListing.created_at.desc()).limit(limit).offset(offset)
        result = await self.session.execute(stmt)
        return list(result.scalars().unique().all()), total_count

    async def update_listing(
        self,
        listing: B2BListing,
        update_data: Dict[str, Any],
    ) -> B2BListing:
        """Actualiza los atributos de una publicación mayorista."""
        for field, value in update_data.items():
            if value is not None and hasattr(listing, field):
                setattr(listing, field, value)
        await self.session.flush()
        await self.session.refresh(listing)
        return listing
