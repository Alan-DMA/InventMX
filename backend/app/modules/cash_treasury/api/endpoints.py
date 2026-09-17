# Importación de módulos de tipado y UUID
from datetime import datetime
from typing import Any, Dict, List, Optional
import uuid

# Importación de FastAPI y componentes de ruteo
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de dependencias de seguridad y base de datos
from app.core.database.session import get_db
from app.core.security.deps import get_current_user, require_permission
from app.modules.auth_tenancy.domain.user import User
from app.modules.cash_treasury.schemas.cash_schemas import (
    CashMovementCreateRequest,
    CashMovementResponse,
    CashSessionCloseRequest,
    CashSessionCloseResponse,
    CashSessionOpenRequest,
    CashSessionReportResponse,
    CashSessionResponse,
)
from app.modules.cash_treasury.services.cash_treasury_service import CashTreasuryService
from app.modules.sales_pos.domain.cash_shift import ShiftStatus

# Router oficial del módulo de Caja y Tesorería
router = APIRouter(prefix="/cash", tags=["Caja & Tesorería"])


@router.get(
    "/sessions",
    response_model=Dict[str, Any],
    status_code=status.HTTP_200_OK,
    summary="Listar sesiones de caja del comercio",
    description="Retorna las sesiones de caja (turnos) con filtros opcionales por cajero y fechas.",
)
async def list_cash_sessions(
    cashier_id: Optional[uuid.UUID] = Query(None, description="Filtrar por cajero específico"),
    status_filter: Optional[ShiftStatus] = Query(None, alias="status", description="Filtrar por estado OPEN o CLOSED"),
    date_from: Optional[datetime] = Query(None, description="Fecha de inicio"),
    date_to: Optional[datetime] = Query(None, description="Fecha de fin"),
    page: int = Query(1, ge=1, description="Número de página"),
    page_size: int = Query(20, ge=1, le=100, description="Registros por página"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
) -> Dict[str, Any]:
    """Lista las sesiones de caja del comercio."""
    service = CashTreasuryService(db)
    return await service.list_sessions(
        tenant_id=current_user.tenant_id,
        cashier_id=cashier_id,
        status_filter=status_filter,
        date_from=date_from,
        date_to=date_to,
        page=page,
        page_size=page_size,
    )


@router.post(
    "/open-session",
    response_model=CashSessionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Abrir nueva sesión de caja (inicio de turno)",
    description="Inicia una nueva sesión de caja con fondo inicial y conteo de piezas Banxico.",
)
async def open_cash_session(
    request: CashSessionOpenRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
) -> CashSessionResponse:
    """Abre formalmente un turno de caja para el cajero autenticado."""
    service = CashTreasuryService(db)
    return await service.open_session(
        tenant_id=current_user.tenant_id,
        cashier_id=current_user.id,
        cashier_name=current_user.full_name or "Cajero",
        request=request,
    )


@router.post(
    "/close-session",
    response_model=CashSessionCloseResponse,
    status_code=status.HTTP_200_OK,
    summary="Cerrar sesión de caja (fin de turno con arqueo Banxico)",
    description="Cierra la sesión activa realizando el arqueo físico y comparando contra el saldo teórico.",
)
async def close_cash_session(
    request: CashSessionCloseRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
) -> CashSessionCloseResponse:
    """Cierra el turno de caja activo con arqueo físico."""
    service = CashTreasuryService(db)
    return await service.close_session(
        tenant_id=current_user.tenant_id,
        cashier_id=current_user.id,
        cashier_name=current_user.full_name or "Cajero",
        request=request,
    )


@router.get(
    "/active-session",
    response_model=Optional[CashSessionResponse],
    status_code=status.HTTP_200_OK,
    summary="Consultar sesión de caja activa del cajero",
    description="Devuelve la sesión actualmente abierta del cajero en sesión, o null si no hay ninguna.",
)
async def get_active_cash_session(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
) -> Optional[CashSessionResponse]:
    """Obtiene la sesión de caja abierta para el cajero actual."""
    service = CashTreasuryService(db)
    return await service.get_active_session(
        tenant_id=current_user.tenant_id,
        cashier_id=current_user.id,
        cashier_name=current_user.full_name or "Cajero",
    )


@router.get(
    "/sessions/{id}",
    response_model=CashSessionResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener detalle de sesión de caja específica",
)
async def get_cash_session_detail(
    id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
) -> CashSessionResponse:
    """Recupera la información completa de una sesión de caja por ID."""
    service = CashTreasuryService(db)
    return await service.get_session_detail(session_id=id, tenant_id=current_user.tenant_id)


@router.get(
    "/sessions/{id}/movements",
    response_model=List[CashMovementResponse],
    status_code=status.HTTP_200_OK,
    summary="Listar movimientos de caja menor de una sesión",
)
async def list_session_movements(
    id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
) -> List[CashMovementResponse]:
    """Lista las entradas y salidas menores de efectivo del turno."""
    service = CashTreasuryService(db)
    return await service.list_movements(session_id=id, tenant_id=current_user.tenant_id)


@router.post(
    "/sessions/{id}/movements",
    response_model=CashMovementResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar movimiento de caja menor",
    description="Registra una salida (WITHDRAWAL) o entrada (DEPOSIT) manual de efectivo afectando el saldo teórico.",
)
async def register_session_movement(
    id: uuid.UUID,
    request: CashMovementCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.checkout")),
) -> CashMovementResponse:
    """Registra un movimiento extraordinario de efectivo en la caja."""
    service = CashTreasuryService(db)
    return await service.register_movement(
        session_id=id,
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        request=request,
    )


@router.get(
    "/sessions/{id}/report",
    response_model=CashSessionReportResponse,
    status_code=status.HTTP_200_OK,
    summary="Generar reporte de corte Z de sesión de caja",
)
async def get_session_z_report(
    id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("sales.view")),
) -> CashSessionReportResponse:
    """Genera el reporte consolidado Z de la sesión de caja."""
    service = CashTreasuryService(db)
    return await service.generate_z_report(session_id=id, tenant_id=current_user.tenant_id)
