# Importación de asyncio para el bucle del WebSocket
import asyncio
# Importación de fecha y hora
from datetime import datetime
# Importación de tipado estático
from typing import Optional
# Importación de identificadores UUID
import uuid

# Importación de FastAPI y componentes de ruteo
from fastapi import APIRouter, Depends, Query, Request, WebSocket, WebSocketDisconnect, status
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de dependencias de infraestructura y seguridad
from app.core.database.session import AsyncSessionLocal, get_db, set_tenant_context
from app.core.security.deps import get_current_user, require_permission
from app.core.security.jwt import decode_token
from app.modules.auth_tenancy.domain.user import User
from app.modules.auth_tenancy.repositories.user_repository import UserRepository
from app.modules.whatsapp_catalog.api.rate_limit import limit_public_orders, limit_public_ticket
# Importación de esquemas Pydantic
from app.modules.whatsapp_catalog.schemas.public_catalog import (
    CatalogOrderResponse,
    StoreOrderEditRequest,
    StoreOrderListResponse,
    StoreOrderResponse,
    StoreOrderStatusUpdate,
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
from app.modules.whatsapp_catalog.services.order_event_hub import order_event_hub
from app.modules.whatsapp_catalog.services.public_catalog_service import PublicCatalogService
from app.modules.whatsapp_catalog.services.store_orders_service import StoreOrdersService

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


@router.post(
    "/public/catalog/{store_slug}/orders",
    response_model=CatalogOrderResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar pedido de la vitrina y asignar folio",
)
async def submit_catalog_order(
    store_slug: str,
    request: WhatsAppOrderBuildRequest,
    db: AsyncSession = Depends(get_db),
    _rate: None = Depends(limit_public_orders),
) -> CatalogOrderResponse:
    """
    Registra el pedido del cliente con un folio corto (RF-24). El chat de WhatsApp lleva
    solo folio, total y enlace al ticket; el detalle completo se consulta con `GET .../orders/{folio}`.
    Mismas validaciones (pedido mínimo, entrega, efectivo) que `build-whatsapp-order`.
    """
    service = PublicCatalogService(db)
    return await service.submit_order(slug=store_slug, request=request)


@router.get(
    "/public/catalog/{store_slug}/orders/{folio}",
    response_model=CatalogOrderResponse,
    status_code=status.HTTP_200_OK,
    summary="Consultar el ticket de un pedido registrado por folio",
)
async def get_catalog_order(
    store_slug: str,
    folio: str,
    k: Optional[str] = Query(None, description="Clave del enlace (viaja en el chat); sin ella, 404"),
    db: AsyncSession = Depends(get_db),
    _rate: None = Depends(limit_public_ticket),
) -> CatalogOrderResponse:
    """
    Devuelve el pedido que el cliente abre desde el enlace del chat. Público pero
    protegido: folio + clave del enlace (el folio solo es adivinable) y límite
    por IP (la página se refresca sola cada 10-30 s; 60/min basta y sobra).
    """
    service = PublicCatalogService(db)
    return await service.get_order(slug=store_slug, folio=folio, access_key=k)


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
    current_user: User = Depends(require_permission("settings.manage_store")),
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
    current_user: User = Depends(require_permission("settings.manage_store")),
) -> CatalogSettingsResponse:
    """Modifica el número de WhatsApp, mensaje de bienvenida, pedido mínimo y costo de envío."""
    service = CatalogSettingsService(db)
    return await service.update_settings(request, current_user)


# -----------------------------------------------------------------------------
# Pedidos web del lado del tendero (autenticado) — plan del 20 sep 2026
# Permisos: leer = sales.view, mover/editar = sales.checkout (los mismos del POS).
# -----------------------------------------------------------------------------

@router.get(
    "/catalog-orders",
    response_model=StoreOrderListResponse,
    summary="Pedidos web del comercio (activos, historial) con badge del servidor",
)
async def list_store_orders(
    scope: str = Query("active", pattern="^(active|history|all)$", description="active = NEW+READY"),
    since: Optional[datetime] = Query(None, description="Sólo lo modificado después (resincronizar tras caída del socket)"),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
) -> StoreOrderListResponse:
    """La lista y el conteo de nuevos siempre salen de aquí; el WebSocket sólo avisa."""
    return await StoreOrdersService(db).list_orders(current_user, scope=scope, since=since, limit=limit)


@router.get(
    "/catalog-orders/{folio}",
    response_model=StoreOrderResponse,
    summary="Detalle de un pedido web (abrirlo lo marca como visto)",
)
async def get_store_order(
    folio: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
) -> StoreOrderResponse:
    return await StoreOrdersService(db).get_order(current_user, folio)


@router.patch(
    "/catalog-orders/{folio}/status",
    response_model=StoreOrderResponse,
    summary="Cambiar estado: Listo · Entregado · Cancelar (con motivo) · Reabrir · ligar venta",
)
async def update_store_order_status(
    folio: str,
    request: StoreOrderStatusUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
) -> StoreOrderResponse:
    """409 si `expected_updated_at` no coincide: alguien más cambió el pedido."""
    return await StoreOrdersService(db).update_status(current_user, folio, request)


@router.put(
    "/catalog-orders/{folio}",
    response_model=StoreOrderResponse,
    summary="Editar el pedido tras cambios acordados por chat (conserva la versión anterior)",
)
async def edit_store_order(
    folio: str,
    request: StoreOrderEditRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
) -> StoreOrderResponse:
    return await StoreOrdersService(db).edit_order(current_user, folio, request)


@router.websocket("/ws/orders")
async def store_orders_socket(websocket: WebSocket, token: str = Query(...)) -> None:
    """
    Canal de avisos en vivo para la app del tendero: `order.new` al registrarse un
    pedido en la vitrina y `order.updated` en cada cambio (visto, estado, edición).
    Autenticación por JWT en query (los navegadores no mandan headers en WebSocket).
    Un `{"type": "ping"}` cada 30 s mantiene viva la conexión; el cliente puede
    mandar cualquier texto (pong) y se ignora.
    """
    # 1. Autenticar antes de aceptar — mismo criterio que get_current_user
    try:
        payload = decode_token(token)
        if payload.get("type") != "access":
            raise ValueError("no es un token de acceso")
        user_id = uuid.UUID(str(payload.get("sub")))
    except Exception:
        await websocket.close(code=4401)
        return

    async with AsyncSessionLocal() as session:
        user = await UserRepository(session).get_by_id(user_id)
        if not user or not user.is_active:
            await websocket.close(code=4401)
            return
        tenant_id = user.tenant_id
        await set_tenant_context(session, tenant_id)

    await websocket.accept()
    queue = order_event_hub.subscribe(tenant_id)

    async def _drain_incoming() -> None:
        # Sólo para detectar el cierre del cliente; los mensajes entrantes no se usan.
        while True:
            await websocket.receive_text()

    receiver = asyncio.create_task(_drain_incoming())
    try:
        await websocket.send_json({"type": "hello", "tenant_id": str(tenant_id)})
        while True:
            if receiver.done():
                break
            try:
                event = await asyncio.wait_for(queue.get(), timeout=30)
            except asyncio.TimeoutError:
                await websocket.send_json({"type": "ping"})
                continue
            await websocket.send_json(event)
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        receiver.cancel()
        order_event_hub.unsubscribe(tenant_id, queue)
