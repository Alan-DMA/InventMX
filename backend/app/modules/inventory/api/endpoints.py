# Importación de tipado estático
from typing import List, Optional
# Importación de UUID para tipado de parámetros de ruta
import uuid
# Importación de FastAPI, cargas de archivos y dependencias
from fastapi import APIRouter, Depends, File, Form, Query, UploadFile, status
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
from app.modules.inventory.domain.inventory_movement import MovementType
# Importación de esquemas Pydantic
from app.modules.inventory.schemas.category import CategoryCreate, CategoryResponse
from app.modules.inventory.schemas.combo import (
    ComboCreate,
    ComboResponse,
    ComboUpdate,
)
from app.modules.inventory.schemas.import_export import (
    ColumnMapping,
    ImportExecutionResponse,
    ImportPreviewResponse,
)
from app.modules.inventory.schemas.movement import (
    InventoryMovementResponse,
    StockAdjustmentCreate,
    StockTransferCreate,
)
from app.modules.inventory.schemas.product import (
    ProductCreateVital,
    ProductListItem,
    ProductResponse,
    ProductUpdate,
)
from app.modules.inventory.schemas.reservation import (
    StockReservationCreate,
    StockReservationResponse,
)
from app.modules.inventory.schemas.seed_product import (
    EanLookupResponse,
    SeedProductResponse,
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


# =============================================================================
# ENDPOINTS DE COMBOS Y PROMOCIONES EN MXN (RF-03)
# =============================================================================

@router.get(
    "/combos",
    response_model=List[ComboResponse],
    summary="Listar promociones y combos con stock dinámico calculable (RF-03)",
)
async def list_combos(
    is_active: Optional[bool] = Query(None, description="Filtrar por estado activo"),
    skip: int = Query(0, ge=0, description="Paginación: registros a omitir"),
    limit: int = Query(100, ge=1, le=500, description="Paginación: límite de registros"),
    current_user: User = Depends(require_permission("inventory.view")),
    db: AsyncSession = Depends(get_db),
):
    """
    Retorna el listado de promociones y combos armados, calculando en tiempo real
    el cuello de botella de existencias disponibles según sus productos componentes.
    """
    service = InventoryService(db)
    return await service.list_combos(
        current_user=current_user, is_active=is_active, skip=skip, limit=limit
    )


@router.get(
    "/combos/{combo_id}",
    response_model=ComboResponse,
    summary="Obtener detalle de combo o promoción por ID",
)
async def get_combo_by_id(
    combo_id: uuid.UUID,
    current_user: User = Depends(require_permission("inventory.view")),
    db: AsyncSession = Depends(get_db),
):
    """
    Retorna el desglose de productos que componen el combo y sus existencias calculadas.
    """
    service = InventoryService(db)
    return await service.get_combo_by_id(combo_id, current_user)


@router.post(
    "/combos",
    response_model=ComboResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Crear nuevo combo o promoción en Pesos Mexicanos (RF-03)",
)
async def create_combo(
    data: ComboCreate,
    current_user: User = Depends(require_permission("inventory.create")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Registra un combo comercial agrupando múltiples productos simples con precio global en MXN.
    """
    service = InventoryService(db)
    return await service.create_combo(data, current_user)


@router.put(
    "/combos/{combo_id}",
    response_model=ComboResponse,
    summary="Actualizar combo o modificar sus productos componentes",
)
async def update_combo(
    combo_id: uuid.UUID,
    data: ComboUpdate,
    current_user: User = Depends(require_permission("inventory.edit_price")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Modifica precio en MXN, estado activo o composición de productos del combo.
    """
    service = InventoryService(db)
    return await service.update_combo(combo_id, data, current_user)


@router.delete(
    "/combos/{combo_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Eliminar combo o promoción",
)
async def delete_combo(
    combo_id: uuid.UUID,
    current_user: User = Depends(require_permission("inventory.delete")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Elimina físicamente un combo del catálogo del comercio.
    """
    service = InventoryService(db)
    await service.delete_combo(combo_id, current_user)


# =============================================================================
# ENDPOINTS DE AJUSTES FÍSICOS Y TRASLADOS MULTI-ALMACÉN (RF-05, RF-07)
# =============================================================================

@router.post(
    "/adjust-stock",
    response_model=InventoryMovementResponse,
    status_code=status.HTTP_200_OK,
    summary="Ajuste manual de existencias físicas con asiento en Kardex (Const. Art. 7.1)",
)
async def adjust_stock(
    data: StockAdjustmentCreate,
    current_user: User = Depends(require_permission("inventory.adjust_stock")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Realiza una modificación directa sobre el inventario (+ Entrada física o - Merma/Salida)
    garantizando consistencia ACID y creando un asiento inmutable en el Kardex.
    """
    service = InventoryService(db)
    return await service.adjust_stock(data, current_user)


@router.post(
    "/transfer-stock",
    response_model=List[InventoryMovementResponse],
    status_code=status.HTTP_200_OK,
    summary="Traslado atómico de existencias entre almacenes (RF-07)",
)
async def transfer_stock(
    data: StockTransferCreate,
    current_user: User = Depends(require_permission("inventory.adjust_stock")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Transfiere mercancía de un almacén origen a un almacén destino en una sola transacción atómica,
    generando los dos asientos correspondientes en el Kardex (TRANSFER_OUT y TRANSFER_IN).
    """
    service = InventoryService(db)
    return await service.transfer_stock(data, current_user)


# =============================================================================
# ENDPOINTS DE CONSULTA DE KARDEX INMUTABLE (RF-05 / Const. Art. 7.1)
# =============================================================================

@router.get(
    "/movements",
    response_model=List[InventoryMovementResponse],
    summary="Consultar historial inmutable de movimientos de inventario (Kardex)",
)
async def list_movements(
    product_id: Optional[uuid.UUID] = Query(None, description="Filtrar por producto"),
    warehouse_id: Optional[uuid.UUID] = Query(None, description="Filtrar por almacén"),
    movement_type: Optional[MovementType] = Query(None, description="Filtrar por tipo de movimiento"),
    skip: int = Query(0, ge=0, description="Paginación: registros a omitir"),
    limit: int = Query(100, ge=1, le=500, description="Paginación: límite de registros"),
    current_user: User = Depends(require_permission("inventory.view")),
    db: AsyncSession = Depends(get_db),
):
    """
    Retorna el libro mayor (Kardex) de movimientos de inventario del comercio con auditoría completa.
    """
    service = InventoryService(db)
    return await service.list_movements(
        current_user=current_user,
        product_id=product_id,
        warehouse_id=warehouse_id,
        movement_type=movement_type,
        skip=skip,
        limit=limit,
    )


# =============================================================================
# ENDPOINTS DE APARTADOS TEMPORALES / STOCK RESERVADO TTL 15 MIN (RF-06)
# =============================================================================

@router.post(
    "/reservations",
    response_model=StockReservationResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Crear apartado temporal de existencias con TTL de 15 min (RF-06)",
)
async def create_reservation(
    data: StockReservationCreate,
    current_user: User = Depends(require_permission("sales.checkout")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Bloquea temporalmente unidades en un almacén para evitar colisiones de venta entre cajeros.
    """
    service = InventoryService(db)
    return await service.create_reservation(data, current_user)


@router.post(
    "/reservations/{reservation_id}/release",
    response_model=StockReservationResponse,
    summary="Liberar manualmente un apartado de existencias activo",
)
async def release_reservation(
    reservation_id: uuid.UUID,
    current_user: User = Depends(require_permission("sales.checkout")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Libera el stock apartado cuando un cliente desiste o cancela la transacción en mostrador.
    """
    service = InventoryService(db)
    return await service.release_reservation(reservation_id, current_user)


@router.post(
    "/reservations/cleanup",
    summary="Worker / Cron para liberar reservas cuyo TTL de 15 minutos ha expirado (RF-06)",
)
async def cleanup_expired_reservations(
    current_user: User = Depends(require_permission("inventory.adjust_stock")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Ejecuta el barrido de apartados vencidos y reincorpora el stock al inventario disponible.
    """
    service = InventoryService(db)
    released_count = await service.cleanup_expired_reservations()
    return {"released_count": released_count, "status": "success"}


# =============================================================================
# ENDPOINT DE CONSULTA DE CÓDIGOS DE BARRAS EAN-13 (RF-29 / Const. Art. 7.5)
# =============================================================================

@router.get(
    "/lookup-ean/{barcode}",
    response_model=EanLookupResponse,
    summary="Consulta instantánea (< 5ms) en Catálogo Semilla Maestro GS1 México (RF-29)",
)
async def lookup_ean(
    barcode: str,
    current_user: User = Depends(require_permission("inventory.view")),
    db: AsyncSession = Depends(get_db),
):
    """
    Busca en el catálogo semilla oficial de México (Tier 1) por código de barras físico.
    Permite autocompletar la ficha comercial en menos de 5ms durante el escaneo en mostrador o góndola.
    """
    service = InventoryService(db)
    return await service.lookup_ean(barcode)


# =============================================================================
# ENDPOINTS DE IMPORTACIÓN FLEXIBLE DE ARCHIVOS EXCEL / CSV (RF-01)
# =============================================================================

@router.post(
    "/import/preview",
    response_model=ImportPreviewResponse,
    summary="Previsualizar archivo Excel/CSV y sugerir mapeo de columnas (RF-01)",
)
async def preview_import_file(
    file: UploadFile = File(..., description="Archivo en formato .xlsx o .csv"),
    current_user: User = Depends(require_permission("inventory.create")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Analiza un archivo Excel o CSV subido por el comerciante, extrayendo los encabezados
    detectados y las primeras filas de muestra para permitir el mapeo visual libre de columnas.
    """
    file_bytes = await file.read()
    service = InventoryService(db)
    return await service.preview_import(file_bytes, file.filename or "archivo.xlsx")


@router.post(
    "/import/execute",
    response_model=ImportExecutionResponse,
    summary="Ejecutar ingesta masiva de inventario con mapeo visual dinámico (RF-01)",
)
async def execute_import_file(
    file: UploadFile = File(..., description="Archivo .xlsx o .csv a procesar"),
    mapping: str = Form(..., description="JSON serializado con el mapeo de columnas ColumnMapping"),
    current_user: User = Depends(require_permission("inventory.create")),
    unlocked_user: User = Depends(require_unlocked_tenant),
    db: AsyncSession = Depends(get_db),
):
    """
    Procesa e inserta atómicamente en PostgreSQL bajo el tenant_id activo todos los artículos
    del archivo conforme a las columnas mapeadas por el usuario, respetando los 3 Campos Vitales
    (Nombre, Precio MXN y Stock) y autogenerando SKUs y asientos en Kardex.
    """
    # Parsear el mapeo de columnas recibido como JSON
    column_mapping = ColumnMapping.model_validate_json(mapping)
    file_bytes = await file.read()
    service = InventoryService(db)
    return await service.execute_import(file_bytes, file.filename or "archivo.xlsx", column_mapping, current_user)

