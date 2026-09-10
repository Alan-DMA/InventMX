# Importación de marcas de fecha
from datetime import datetime
# Importación de precisión decimal
from decimal import Decimal
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
from app.modules.sales_pos.domain.cash_movement import CashMovementType
from app.modules.sales_pos.domain.cash_shift import DifferenceStatus, ShiftStatus
from app.modules.sales_pos.domain.commission import CommissionType
from app.modules.sales_pos.domain.sale import SaleStatus
from app.modules.sales_pos.schemas.cash_shift import (
    CashMovementCreateRequest,
    CashMovementResponse,
    CashShiftCloseRequest,
    CashShiftOpenRequest,
    CashShiftResponse,
    CashShiftSummaryResponse,
)
from app.modules.sales_pos.schemas.commission import (
    CommissionSummaryResponse,
    SaleCommissionResponse,
)
from app.modules.sales_pos.schemas.payment import (
    PaymentRequest,
    PaymentResponse,
    QuickChangeRequest,
    QuickChangeResponse,
)
from app.modules.sales_pos.schemas.sale import (
    SaleCancelRequest,
    SaleCheckoutRequest,
    SaleResponse,
)
from app.modules.sales_pos.schemas.ticket import (
    TicketPayloadResponse,
    TicketSettingsResponse,
    TicketSettingsUpdateRequest,
)
from app.modules.sales_pos.services.sales_service import SalesService

# Instanciación del router para el módulo de Ventas, Checkout POS, Pagos, Tickets, Comisiones y Turnos de Caja
router = APIRouter(prefix="/sales", tags=["Sales & POS Checkout"])


# =============================================================================
# ENDPOINTS DE CHECKOUT Y CAJA
# =============================================================================

@router.post(
    "/checkout",
    response_model=SaleResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Procesar Checkout Atómico en Punto de Venta (POS)",
    description=(
        "Ejecuta una transacción de venta ACID en mostrador con soporte de pagos mixtos (RF-13, RF-14). "
        "Bloquea existencias con SELECT FOR UPDATE, congela precios y costos históricos, descuenta stock, "
        "soporta combos y creación al vuelo (Lazy Loading RF-09), registra los pagos y genera asientos en Kardex."
    ),
)
async def checkout_sale(
    request: SaleCheckoutRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
    _unlocked: None = Depends(require_unlocked_tenant),
):
    """
    Endpoint principal de cobro en mostrador (POS Checkout) con pagos mixtos.
    """
    service = SalesService(db)
    return await service.process_pos_checkout(request, current_user)


@router.post(
    "/quick-change",
    response_model=QuickChangeResponse,
    status_code=status.HTTP_200_OK,
    summary="Calculadora Rápida de Cambio y Vuelto Banxico (POS)",
    description=(
        "Calcula instantáneamente el cambio a entregar en mostrador y sugiere el desglose óptimo "
        "en billetes y monedas del cono monetario oficial del Banco de México (RF-14 / Const. Art. 7.2)."
    ),
)
async def calculate_quick_change(
    request: QuickChangeRequest,
    current_user: User = Depends(require_permission("sales.view")),
    db: AsyncSession = Depends(get_db),
):
    """
    Calculadora de cambio rápido con desglose Banxico.
    """
    service = SalesService(db)
    return service.calculate_quick_change(request.total_mxn, request.cash_received_mxn)


# =============================================================================
# ENDPOINTS DE TURNOS DE CAJA Y ARQUEO (ESTÁTICOS ANTES DE /{sale_id})
# =============================================================================

@router.post(
    "/shifts/open",
    response_model=CashShiftResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Apertura de Turno de Caja (Sesión de Cajero)",
    description="Inicia una nueva jornada de caja con fondo inicial en MXN. Valida que no exista turno activo previo (RF-16 / Const. Art. 3.3).",
)
async def open_shift(
    request: CashShiftOpenRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
    _unlocked: None = Depends(require_unlocked_tenant),
):
    """
    Apertura formal de turno de caja para el cajero en sesión.
    """
    service = SalesService(db)
    return await service.open_cash_shift(
        tenant_id=current_user.tenant_id,
        cashier_id=current_user.id,
        request=request,
    )


@router.get(
    "/shifts/current",
    response_model=Optional[CashShiftResponse],
    status_code=status.HTTP_200_OK,
    summary="Consultar Turno de Caja Activo del Cajero Actual",
    description="Devuelve el turno actualmente en estado OPEN del cajero autenticado, o null si la caja está cerrada.",
)
async def get_current_shift(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
):
    """
    Recupera el turno de caja abierto del cajero en sesión.
    """
    service = SalesService(db)
    return await service.get_current_cash_shift(
        tenant_id=current_user.tenant_id,
        cashier_id=current_user.id,
    )


@router.get(
    "/shifts",
    response_model=List[CashShiftResponse],
    status_code=status.HTTP_200_OK,
    summary="Listar Historial de Turnos de Caja",
    description="Permite auditar el historial de turnos con filtros por cajero, estado y rango de fechas (RF-16, RF-17).",
)
async def list_shifts(
    cashier_id: Optional[uuid.UUID] = Query(None, description="Filtrar por cajero específico"),
    status_filter: Optional[ShiftStatus] = Query(None, alias="status", description="Filtrar por estado OPEN o CLOSED"),
    start_date: Optional[datetime] = Query(None, description="Fecha inicial del periodo"),
    end_date: Optional[datetime] = Query(None, description="Fecha final del periodo"),
    skip: int = Query(0, ge=0, description="Paginación offset"),
    limit: int = Query(50, ge=1, le=100, description="Límite por página"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
):
    """
    Historial paginado de turnos de caja para auditoría de comercio.
    """
    service = SalesService(db)
    return await service.list_cash_shifts(
        tenant_id=current_user.tenant_id,
        cashier_id=cashier_id,
        status=status_filter,
        start_date=start_date,
        end_date=end_date,
        limit=limit,
        offset=skip,
    )


@router.get(
    "/shifts/{shift_id}/summary",
    response_model=CashShiftSummaryResponse,
    status_code=status.HTTP_200_OK,
    summary="Resumen Financiero y Saldo Teórico Esperado de un Turno",
    description="Calcula las ventas acumuladas por método de pago, movimientos manuales y saldo teórico esperado en efectivo (RF-16, RF-17).",
)
async def get_shift_summary(
    shift_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
):
    """
    Calcula el resumen financiero y arqueo del turno.
    """
    service = SalesService(db)
    return await service.get_shift_financial_summary(
        tenant_id=current_user.tenant_id,
        shift_id=shift_id,
    )


@router.post(
    "/shifts/{shift_id}/movements",
    response_model=CashMovementResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar Movimiento Manual de Efectivo (CASH_IN / CASH_OUT)",
    description="Registra una entrada (depósito de cambio) o salida (gasto menor, retiro parcial) en el turno activo (RF-16).",
)
async def record_cash_movement(
    shift_id: uuid.UUID,
    request: CashMovementCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
    _unlocked: None = Depends(require_unlocked_tenant),
):
    """
    Registro inmutable de movimiento manual en caja chica.
    """
    service = SalesService(db)
    return await service.record_cash_movement(
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        shift_id=shift_id,
        request=request,
    )


@router.post(
    "/shifts/{shift_id}/close",
    response_model=CashShiftResponse,
    status_code=status.HTTP_200_OK,
    summary="Arqueo a Ciegas y Cierre de Turno de Caja",
    description="Cierra formalmente el turno congelando el conteo físico ingresado y calculando la discrepancia (RF-17 / Const. Art. 7.2).",
)
async def close_shift(
    shift_id: uuid.UUID,
    request: CashShiftCloseRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
    _unlocked: None = Depends(require_unlocked_tenant),
):
    """
    Cierre de turno y cálculo del arqueo de caja a ciegas.
    """
    service = SalesService(db)
    return await service.close_cash_shift(
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        shift_id=shift_id,
        request=request,
    )


@router.get(
    "/shifts/{shift_id}",
    response_model=CashShiftResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener Detalle Completo de un Turno de Caja",
    description="Devuelve la información detallada del turno con su lista de movimientos manuales asociados.",
)
async def get_shift_details(
    shift_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
):
    """
    Detalle de un turno de caja por su ID.
    """
    service = SalesService(db)
    return await service.get_cash_shift_details(
        tenant_id=current_user.tenant_id,
        shift_id=shift_id,
    )


# =============================================================================
# ENDPOINTS DE CONFIGURACIÓN DE TICKETS (ESTÁTICOS ANTES DE /{sale_id})
# =============================================================================

@router.get(
    "/settings/ticket",
    response_model=TicketSettingsResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener Configuración de Tickets Térmicos de la Tienda",
    description="Recupera los parámetros de cabecera, RFC, dirección, mensaje de pie y ancho de papel (58mm/80mm) (RF-08).",
)
async def get_ticket_settings(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
):
    """
    Consulta de configuración de tickets térmicos del comercio.
    """
    service = SalesService(db)
    return await service.get_ticket_settings(current_user)


@router.put(
    "/settings/ticket",
    response_model=TicketSettingsResponse,
    status_code=status.HTTP_200_OK,
    summary="Actualizar Configuración de Tickets Térmicos de la Tienda",
    description="Actualiza la identidad visual, datos fiscales simplificados, mensajes de despedida y ancho de papel del ticket (RF-08).",
)
async def update_ticket_settings(
    request: TicketSettingsUpdateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
    _unlocked: None = Depends(require_unlocked_tenant),
):
    """
    Actualización de parámetros del ticket térmico en el comercio.
    """
    service = SalesService(db)
    return await service.update_ticket_settings(request, current_user)


# =============================================================================
# ENDPOINTS DE COMISIONES (ESTÁTICOS ANTES DE /{sale_id})
# =============================================================================

@router.get(
    "/commissions/summary",
    response_model=CommissionSummaryResponse,
    status_code=status.HTTP_200_OK,
    summary="Consultar Resumen de Comisiones de Venta por Empleado",
    description="Permite consultar el acumulado de comisiones ganadas por cajeros/vendedores en un rango de fechas (RF-10 / Const. Art. 8.2).",
)
async def get_commissions_summary(
    user_id: Optional[uuid.UUID] = Query(None, description="Filtrar comisiones por empleado específico"),
    start_date: Optional[datetime] = Query(None, description="Fecha inicial del periodo (ISO 8601)"),
    end_date: Optional[datetime] = Query(None, description="Fecha final del periodo (ISO 8601)"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
):
    """
    Reporte consolidado de comisiones de venta para el comercio.
    """
    service = SalesService(db)
    return await service.get_commissions_summary(
        current_user=current_user,
        user_id=user_id,
        start_date=start_date,
        end_date=end_date,
    )


# =============================================================================
# ENDPOINTS DE PAGOS, TICKETS Y GESTIÓN POR VENTA ESPECÍFICA
# =============================================================================

@router.get(
    "/{sale_id}/ticket",
    response_model=TicketPayloadResponse,
    status_code=status.HTTP_200_OK,
    summary="Generar Nota de Venta / Ticket Térmico POS (58mm / 80mm)",
    description=(
        "Devuelve el payload estructurado y el texto plano pre-formateado monoespaciado listo para impresión "
        "en impresoras térmicas de 58 mm (32 cols) u 80 mm (48 cols) (RF-08 / Const. Art. 1.2.8)."
    ),
)
async def get_sale_ticket(
    sale_id: uuid.UUID,
    width_mm: Optional[int] = Query(None, description="Ancho de papel térmico (58 u 80). Si es None se usa el predeterminado"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
):
    """
    Generación de comprobante simplificado y formateo de impresión térmica.
    """
    service = SalesService(db)
    return await service.generate_sale_ticket(sale_id, width_mm, current_user)


@router.post(
    "/{sale_id}/commissions",
    response_model=SaleCommissionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar Comisión de Venta Dinámica para Empleado",
    description="Calcula y asienta la comisión devengada por un cajero o vendedor en una venta concretada (RF-10).",
)
async def record_commission(
    sale_id: uuid.UUID,
    user_id: uuid.UUID = Query(..., description="ID del usuario empleado beneficiario"),
    commission_type: CommissionType = Query(CommissionType.PERCENTAGE_SALE, description="Tipo de comisión aplicada"),
    commission_rate: Decimal = Query(..., ge=0, description="Tasa porcentual o importe fijo en $ MXN"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
    _unlocked: None = Depends(require_unlocked_tenant),
):
    """
    Registro contable inmutable de comisión devengada por venta.
    """
    service = SalesService(db)
    return await service.record_sale_commission(
        sale_id=sale_id,
        user_id=user_id,
        commission_type=commission_type,
        commission_rate=commission_rate,
        current_user=current_user,
    )


@router.post(
    "/{sale_id}/payments",
    response_model=SaleResponse,
    status_code=status.HTTP_200_OK,
    summary="Registrar Abono o Pago a Venta Existente",
    description=(
        "Añade un abono contable a una venta en estado PENDING_PAYMENT o DRAFT. Si el saldo acumulado "
        "liquida la venta, transiciona automáticamente a estado COMPLETED."
    ),
)
async def add_payment(
    sale_id: uuid.UUID,
    request: PaymentRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
    _unlocked: None = Depends(require_unlocked_tenant),
):
    """
    Registro contable de pago/abono diferido para una venta.
    """
    service = SalesService(db)
    return await service.add_payment_to_sale(sale_id, request, current_user)


@router.get(
    "/{sale_id}",
    response_model=SaleResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener Detalle de Nota de Venta por ID",
    description="Recupera la nota de venta completa con el desglose de partidas, pagos y márgenes bajo aislamiento RLS.",
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
    return await service.list_sales(
        current_user=current_user,
        start_date=start_date,
        end_date=end_date,
        cashier_id=cashier_id,
        warehouse_id=warehouse_id,
        status_filter=status_filter,
        skip=skip,
        limit=limit,
    )


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
