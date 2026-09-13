# Importación de precisión decimal para Pesos Mexicanos
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid

# Importación de FastAPI y componentes de ruteo
from fastapi import APIRouter, Depends, Query, status
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de dependencias de infraestructura y seguridad
from app.core.database.session import get_db
from app.core.security.deps import get_current_user
from app.modules.auth_tenancy.domain.user import User
from app.modules.community_catalog.domain.b2b_order import B2BOrderStatus
# Importación de esquemas Pydantic
from app.modules.community_catalog.schemas.b2b_marketplace import (
    B2BListingCreateRequest,
    B2BListingResponse,
    B2BListingUpdateRequest,
)
from app.modules.community_catalog.schemas.b2b_order import (
    B2BOrderCreateRequest,
    B2BOrderResponse,
    B2BOrderStatusUpdateRequest,
)
# Importación de servicios de negocio
from app.modules.community_catalog.services.b2b_marketplace_service import B2BMarketplaceService
from app.modules.community_catalog.services.b2b_order_service import B2BOrderService

# Router del Catálogo Comunitario B2B
router = APIRouter(prefix="/b2b", tags=["Community B2B & Wholesale"])


# -----------------------------------------------------------------------------
# Endpoints de Publicaciones Mayoristas B2B
# -----------------------------------------------------------------------------

@router.post(
    "/listings",
    response_model=B2BListingResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Publicar oferta mayorista en el catálogo comunitario",
)
async def create_b2b_listing(
    request: B2BListingCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> B2BListingResponse:
    """Publica un lote de productos a precio mayorista en $ MXN (RF-27)."""
    service = B2BMarketplaceService(db)
    return await service.create_listing(request, current_user)


@router.get(
    "/my-listings",
    response_model=List[B2BListingResponse],
    status_code=status.HTTP_200_OK,
    summary="Listar publicaciones mayoristas del comercio actual",
)
async def get_my_b2b_listings(
    is_active: Optional[bool] = Query(None, description="Filtrar por estado activo/inactivo"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[B2BListingResponse]:
    """Retorna las ofertas mayoristas publicadas por el comercio."""
    service = B2BMarketplaceService(db)
    return await service.get_my_listings(current_user, is_active)


@router.put(
    "/listings/{listing_id}",
    response_model=B2BListingResponse,
    status_code=status.HTTP_200_OK,
    summary="Actualizar oferta mayorista",
)
async def update_b2b_listing(
    listing_id: uuid.UUID,
    request: B2BListingUpdateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> B2BListingResponse:
    """Actualiza precios en MXN, stock de mayoreo o estado de la publicación."""
    service = B2BMarketplaceService(db)
    return await service.update_listing(listing_id, request, current_user)


@router.get(
    "/marketplace",
    response_model=List[B2BListingResponse],
    status_code=status.HTTP_200_OK,
    summary="Explorar catálogo comunitario B2B con filtros geográficos y precio",
)
async def search_b2b_marketplace(
    search: Optional[str] = Query(None, description="Búsqueda por nombre de producto o SKU"),
    city: Optional[str] = Query(None, description="Filtrar por ciudad o municipio"),
    postal_code: Optional[str] = Query(None, description="Filtrar por código postal"),
    max_price: Optional[Decimal] = Query(None, description="Precio máximo mayorista en $ MXN"),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[B2BListingResponse]:
    """Explora ofertas publicadas por otros comercios afiliados a la red comunitaria."""
    service = B2BMarketplaceService(db)
    items, _ = await service.search_marketplace(
        current_user=current_user,
        search=search,
        city=city,
        postal_code=postal_code,
        max_price=max_price,
        limit=limit,
        offset=offset,
    )
    return items


# -----------------------------------------------------------------------------
# Endpoints de Transacciones y Pedidos Mayoristas B2B
# -----------------------------------------------------------------------------

@router.post(
    "/orders",
    response_model=B2BOrderResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Emitir solicitud de pedido mayorista a otro comercio",
)
async def create_b2b_order(
    request: B2BOrderCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> B2BOrderResponse:
    """Emite un pedido B2B validando lotes mínimos y stock disponible (RF-27 / Const. Art. 7.5)."""
    service = B2BOrderService(db)
    return await service.create_b2b_order(request, current_user)


@router.get(
    "/orders/sent",
    response_model=List[B2BOrderResponse],
    status_code=status.HTTP_200_OK,
    summary="Listar pedidos mayoristas emitidos (como comprador)",
)
async def list_sent_b2b_orders(
    status_filter: Optional[B2BOrderStatus] = Query(None, alias="status", description="Filtrar por estado"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[B2BOrderResponse]:
    """Retorna los pedidos B2B emitidos por el comercio."""
    service = B2BOrderService(db)
    return await service.list_sent_orders(current_user, status_filter)


@router.get(
    "/orders/received",
    response_model=List[B2BOrderResponse],
    status_code=status.HTTP_200_OK,
    summary="Listar pedidos mayoristas recibidos (como vendedor)",
)
async def list_received_b2b_orders(
    status_filter: Optional[B2BOrderStatus] = Query(None, alias="status", description="Filtrar por estado"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[B2BOrderResponse]:
    """Retorna los pedidos mayoristas que otros comercios han solicitado."""
    service = B2BOrderService(db)
    return await service.list_received_orders(current_user, status_filter)


@router.patch(
    "/orders/{order_id}/status",
    response_model=B2BOrderResponse,
    status_code=status.HTTP_200_OK,
    summary="Actualizar estado del pedido B2B (Aceptar, Rechazar, Completar o Cancelar)",
)
async def update_b2b_order_status(
    order_id: uuid.UUID,
    request: B2BOrderStatusUpdateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> B2BOrderResponse:
    """Gestiona el flujo transaccional del pedido entre comprador y vendedor."""
    service = B2BOrderService(db)
    return await service.update_order_status(order_id, request, current_user)
