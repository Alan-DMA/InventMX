# Importación de tipado estático
from typing import List, Optional
# Importación de UUID para tipado de parámetros de ruta
import uuid
# Importación de FastAPI y dependencias
from fastapi import APIRouter, Depends, Query, status
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de la dependencia del pool de conexiones
from app.core.database.session import get_db
# Importación de dependencias de autenticación y autorización RBAC
from app.core.security.deps import (
    get_current_user,
    require_active_tenant,
    require_permission,
    require_unlocked_tenant,
)
# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.user import User
# Importación de esquemas Pydantic
from app.modules.inventory.schemas.category import CategoryCreate, CategoryResponse
from app.modules.inventory.schemas.product import (
    ProductCreateVital,
    ProductListItem,
    ProductResponse,
    ProductUpdate,
)
from app.modules.inventory.schemas.warehouse import WarehouseCreate, WarehouseResponse
# Importación del servicio de negocio de inventario
from app.modules.inventory.services.inventory_service import InventoryService

# Instanciación del router de inventario
router = APIRouter(prefix="/inventory", tags=["Inventory"])


# =============================================================================
# ENDPOINTS DE PRODUCTOS (3 CAMPOS VITALES, CATÁLOGO Y POS)
# =============================================================================

@router.get(
    "/products",
    response_model=List[ProductResponse],
    summary="Listar catálogo de productos con filtros y búsqueda difusa",
)
async def list_products(
    category_id: Optional[uuid.UUID] = Query(None, description="Filtrar por categoría"),
    is_active: Optional[bool] = Query(None, description="Filtrar por estado activo/inactivo"),
    q: Optional[str] = Query(None, description="Búsqueda rápida por nombre, SKU o código de barras"),
    low_stock: Optional[bool] = Query(None, description="Filtrar productos con stock crítico"),
    skip: int = Query(0, ge=0, description="Paginación: registros a omitir"),
    limit: int = Query(100, ge=1, le=500, description="Paginación: límite de registros"),
    current_user: User = Depends(require_permission("inventory.view")),
    db: AsyncSession = Depends(get_db),
):
    """
    Retorna el catálogo maestro de productos del comercio con soporte de:
    - Búsqueda difusa por trigramas en < 10ms (`q=cocacola`)
    - Filtro por código de barras físico (`q=7501055300075`)
    - Alertas de existencias bajas (`low_stock=true`)
    """
    service = InventoryService(db)
    return await service.list_products(
        current_user=current_user,
        category_id=category_id,
        is_active=is_active,
        query=q,
        is_low_stock=low_stock,
        skip=skip,
        limit=limit,
    )


@router.get(
    "/products/{product_id}",
    response_model=ProductResponse,
    summary="Obtener detalle de producto por ID",
)
async def get_product_by_id(
    product_id: uuid.UUID,
    current_user: User = Depends(require_permission("inventory.view")),
    db: AsyncSession = Depends(get_db),
):
    """
    Retorna la ficha técnica detallada de un producto incluyendo su desglose
    de existencias por almacén y margen de ganancia comercial.
    """
    service = InventoryService(db)
    return await service.get_product_by_id(product_id, current_user)


@router.post(
    "/products",
    response_model=ProductResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Alta express con Formulario Minimalista de 3 Campos Vitales (SR-08)",
)
async def create_product(
    data: ProductCreateVital,
    current_user: User = Depends(require_permission("inventory.create")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Registra un producto al instante con la regla sagrada de los 3 Campos Vitales:
    - **name**: Nombre comercial
    - **price_mxn**: Precio de venta en Pesos Mexicanos
    - **initial_stock**: Existencias iniciales
    Autogenera SKU 'NEX-XXXXX', categoría 'General' y almacén principal si se omiten.
    """
    service = InventoryService(db)
    return await service.create_product_vital(data, current_user)


@router.put(
    "/products/{product_id}",
    response_model=ProductResponse,
    summary="Actualizar datos de producto existente",
)
async def update_product(
    product_id: uuid.UUID,
    data: ProductUpdate,
    current_user: User = Depends(require_permission("inventory.edit_price")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Actualiza la información comercial de un producto (precios en MXN, costos, SKU, etc.).
    """
    service = InventoryService(db)
    return await service.update_product(product_id, data, current_user)


@router.delete(
    "/products/{product_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Eliminar producto del inventario",
)
async def delete_product(
    product_id: uuid.UUID,
    current_user: User = Depends(require_permission("inventory.delete")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Elimina físicamente un producto del catálogo maestro.
    """
    service = InventoryService(db)
    await service.delete_product(product_id, current_user)


# =============================================================================
# ENDPOINTS DE CATEGORÍAS
# =============================================================================

@router.get(
    "/categories",
    response_model=List[CategoryResponse],
    summary="Listar categorías de productos del comercio",
)
async def list_categories(
    current_user: User = Depends(require_permission("inventory.view")),
    db: AsyncSession = Depends(get_db),
):
    """
    Retorna el listado completo de categorías pertenecientes al comercio.
    """
    service = InventoryService(db)
    return await service.list_categories(current_user)


@router.post(
    "/categories",
    response_model=CategoryResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Crear nueva categoría de productos",
)
async def create_category(
    data: CategoryCreate,
    current_user: User = Depends(require_permission("inventory.create")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Registra una nueva categoría de clasificación.
    """
    service = InventoryService(db)
    return await service.create_category(data, current_user)


# =============================================================================
# ENDPOINTS DE ALMACENES
# =============================================================================

@router.get(
    "/warehouses",
    response_model=List[WarehouseResponse],
    summary="Listar almacenes y sucursales del comercio",
)
async def list_warehouses(
    current_user: User = Depends(require_permission("inventory.view")),
    db: AsyncSession = Depends(get_db),
):
    """
    Retorna la lista de almacenes físicos registrados.
    """
    service = InventoryService(db)
    return await service.list_warehouses(current_user)


@router.post(
    "/warehouses",
    response_model=WarehouseResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar nuevo almacén",
)
async def create_warehouse(
    data: WarehouseCreate,
    current_user: User = Depends(require_permission("inventory.create")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Crea una nueva ubicación física de almacén.
    """
    service = InventoryService(db)
    return await service.create_warehouse(data, current_user)
