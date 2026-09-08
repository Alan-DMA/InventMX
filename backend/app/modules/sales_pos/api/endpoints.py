# Importación de marcas de fecha
from datetime import datetime
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de FastAPI
from fastapi import APIRouter, Depends, Query, status
# Importación de sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de dependencias de seguridad y contexto
from app.core.database.session import get_db
from app.core.security.deps import (
    get_current_user,
    require_permission,
    require_unlocked_tenant,
)
from app.modules.auth_tenancy.domain.user import User
from app.modules.sales_pos.domain.sale import SaleStatus
from app.modules.sales_pos.schemas.sale import (
    SaleCancelRequest,
    SaleCheckoutRequest,
    SaleResponse,
)
from app.modules.sales_pos.services.sales_service import SalesService

# Instanciación del router para el módulo de Ventas y Checkout POS
router = APIRouter(prefix="/sales", tags=["Sales & POS Checkout"])


@router.post(
    "/checkout",
    response_model=SaleResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Procesar Checkout Atómico en Punto de Venta (POS)",
    description=(
        "Ejecuta una transacción de venta ACID en mostrador. Bloquea existencias con SELECT FOR UPDATE, "
        "congela precios y costos históricos, descuenta stock, soporta combos y creación al vuelo (Lazy Loading RF-09) "
        "y genera asientos inmutables en el Kardex."
    ),
)
async def checkout_sale(
    request: SaleCheckoutRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
    _unlocked: None = Depends(require_unlocked_tenant),
):
    """
    Endpoint principal de cobro en mostrador (POS Checkout).
    """
    service = SalesService(db)
    return await service.process_pos_checkout(request, current_user)


@router.get(
    "/{sale_id}",
    response_model=SaleResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener Detalle de Nota de Venta por ID",
    description="Recupera la nota de venta completa con el desglose de partidas y márgenes bajo aislamiento RLS.",
)
async def get_sale(
    sale_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
):
    """
    Consulta detallada de una nota de venta por su identificador único.
    """
    service = SalesService(db)
    return await service.get_sale_by_id(sale_id, current_user)


@router.get(
    "",
    response_model=List[SaleResponse],
    status_code=status.HTTP_200_OK,
    summary="Listar Historial de Ventas con Filtros y Paginación",
    description="Permite consultar el historial de ventas filtrando por rango de fechas, cajero, estado o almacén.",
)
async def list_sales(
    start_date: Optional[datetime] = Query(None, description="Fecha inicial del filtro (ISO 8601)"),
    end_date: Optional[datetime] = Query(None, description="Fecha final del filtro (ISO 8601)"),
    cashier_id: Optional[uuid.UUID] = Query(None, description="Filtrar por cajero"),
    warehouse_id: Optional[uuid.UUID] = Query(None, description="Filtrar por almacén"),
    status_filter: Optional[SaleStatus] = Query(None, description="Filtrar por estado de venta"),
    skip: int = Query(0, ge=0, description="Número de registros a omitir (offset)"),
    limit: int = Query(50, ge=1, le=100, description="Número máximo de registros por página"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
):
    """
    Listado paginado de ventas del comercio.
    """
    service = SalesService(db)
    sales, _ = await service.list_sales(
        current_user=current_user,
        start_date=start_date,
        end_date=end_date,
        cashier_id=cashier_id,
        warehouse_id=warehouse_id,
        status_filter=status_filter,
        skip=skip,
        limit=limit,
    )
    return sales


@router.post(
    "/{sale_id}/cancel",
    response_model=SaleResponse,
    status_code=status.HTTP_200_OK,
    summary="Cancelar o Anular una Venta Registrada",
    description=(
        "Cancela una venta, cambia su estado a CANCELLED, reincorpora las existencias vendidas al almacén "
        "y genera asientos compensatorios inmutables en el Kardex (SALE_CANCEL)."
    ),
)
async def cancel_sale(
    sale_id: uuid.UUID,
    request: SaleCancelRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.cancel")),
    _unlocked: None = Depends(require_unlocked_tenant),
):
    """
    Anulación transaccional de venta y reversión de inventario en Kardex.
    """
    service = SalesService(db)
    return await service.cancel_sale(sale_id, request.reason, current_user)
