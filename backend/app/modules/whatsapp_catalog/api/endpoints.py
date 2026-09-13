# Importación de tipado estático
from typing import Optional
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
# Importación de esquemas Pydantic
from app.modules.whatsapp_catalog.schemas.public_catalog import (
    CatalogSettingsResponse,
    CatalogSettingsUpdateRequest,
    OpenGraphMetaResponse,
    PublicCatalogResponse,
    PublicProductDetailResponse,
    WhatsAppOrderBuildRequest,
    WhatsAppOrderBuildResponse,
)
# Importación de servicios de negocio
from app.modules.whatsapp_catalog.services.catalog_settings_service import CatalogSettingsService
from app.modules.whatsapp_catalog.services.public_catalog_service import PublicCatalogService

# Creación del router para el Catálogo Digital de WhatsApp
router = APIRouter(tags=["WhatsApp Catalog & Web"])


# -----------------------------------------------------------------------------
# Endpoints Públicos (Sin autenticación requerida para clientes finales)
# -----------------------------------------------------------------------------

@router.get(
    "/public/catalog/{store_slug}",
    response_model=PublicCatalogResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener catálogo web público de la tienda por slug",
)
async def get_public_catalog(
    store_slug: str,
    category_id: Optional[uuid.UUID] = Query(None, description="Filtrar por categoría"),
    search: Optional[str] = Query(None, description="Búsqueda por nombre o SKU"),
    db: AsyncSession = Depends(get_db),
) -> PublicCatalogResponse:
    """
    Retorna la lista de productos activos disponibles y datos generales del comercio (RF-23).
    Endpoint público abierto a clientes sin requerir token JWT.
    """
    service = PublicCatalogService(db)
    return await service.get_public_catalog(
        slug=store_slug,
        category_id=category_id,
        search=search,
    )


@router.get(
    "/public/catalog/{store_slug}/products/{product_id}",
    response_model=PublicProductDetailResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener detalle individual de producto público",
)
async def get_public_product_detail(
    store_slug: str,
    product_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> PublicProductDetailResponse:
    """
    Retorna la ficha pública de un producto específico para visualización y compartir en redes.
    """
    service = PublicCatalogService(db)
    return await service.get_public_product_detail(
        slug=store_slug,
        product_id=product_id,
    )


@router.post(
    "/public/catalog/{store_slug}/build-whatsapp-order",
    response_model=WhatsAppOrderBuildResponse,
    status_code=status.HTTP_200_OK,
    summary="Construir pedido estructurado y enlace universal wa.me",
)
async def build_whatsapp_order(
    store_slug: str,
    request: WhatsAppOrderBuildRequest,
    db: AsyncSession = Depends(get_db),
) -> WhatsAppOrderBuildResponse:
    """
    Calcula el total del pedido en $ MXN, valida pedido mínimo y entrega, y devuelve el enlace wa.me (RF-24).
    """
    service = PublicCatalogService(db)
    return await service.build_whatsapp_order(
        slug=store_slug,
        request=request,
    )


@router.get(
    "/public/catalog/{store_slug}/og-metadata",
    response_model=OpenGraphMetaResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener metadatos OpenGraph para Server-Side Rendering (SSR)",
)
async def get_og_metadata(
    store_slug: str,
    product_id: Optional[uuid.UUID] = Query(None, description="ID opcional de producto específico"),
    db: AsyncSession = Depends(get_db),
) -> OpenGraphMetaResponse:
    """
    Retorna etiquetas OpenGraph (og:title, og:description, og:image, og:price) para previsualización enriquecida (Const. Art. 7.4).
    """
    service = PublicCatalogService(db)
    return await service.get_og_metadata(
        slug=store_slug,
        product_id=product_id,
    )


# -----------------------------------------------------------------------------
# Endpoints Autenticados (Configuración del catálogo por el comercio)
# -----------------------------------------------------------------------------

@router.get(
    "/catalog-settings",
    response_model=CatalogSettingsResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener configuración del catálogo digital del comercio",
)
async def get_catalog_settings(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> CatalogSettingsResponse:
    """Retorna la configuración operativa del catálogo del tenant actual (RF-26)."""
    service = CatalogSettingsService(db)
    return await service.get_settings(current_user)


@router.put(
    "/catalog-settings",
    response_model=CatalogSettingsResponse,
    status_code=status.HTTP_200_OK,
    summary="Actualizar configuración del catálogo digital",
)
async def update_catalog_settings(
    request: CatalogSettingsUpdateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> CatalogSettingsResponse:
    """Modifica el número de WhatsApp, mensaje de bienvenida, pedido mínimo y costo de envío."""
    service = CatalogSettingsService(db)
    return await service.update_settings(request, current_user)
