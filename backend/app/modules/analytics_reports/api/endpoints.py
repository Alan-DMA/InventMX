# Importación del módulo datetime
from datetime import datetime
# Importación de tipado estático
from typing import Optional

# Importación de FastAPI y componentes de ruteo
from fastapi import APIRouter, Depends, Query, status
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de dependencias de infraestructura y seguridad
from app.core.database.session import get_db
from app.core.security.deps import get_current_user
from app.modules.auth_tenancy.domain.user import User
from app.modules.analytics_reports.schemas.analytics_schemas import (
    CashFlowSummaryResponse,
    DateRangePreset,
    ExecutiveFinancialSummaryResponse,
    InventoryHealthResponse,
    WorkingCapitalResponse,
)
from app.modules.analytics_reports.services.financial_analytics_service import FinancialAnalyticsService

# Router del Módulo de Finanzas y Analítica
router = APIRouter(prefix="/analytics", tags=["Finance & Analytics"])


@router.get(
    "/financial-summary",
    response_model=ExecutiveFinancialSummaryResponse,
    status_code=status.HTTP_200_OK,
    summary="Resumen Financiero Ejecutivo (Ventas, COGS, Utilidad y Margen)",
)
async def get_financial_summary(
    preset: Optional[DateRangePreset] = Query(DateRangePreset.THIS_MONTH, description="Rango predefinido de fechas"),
    start_date: Optional[datetime] = Query(None, description="Fecha de inicio personalizada"),
    end_date: Optional[datetime] = Query(None, description="Fecha de fin personalizada"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ExecutiveFinancialSummaryResponse:
    """Retorna los KPIs ejecutivos de rentabilidad en Pesos Mexicanos ($ MXN) (RF-18 / Const. Art. 7.6)."""
    service = FinancialAnalyticsService(db)
    return await service.get_executive_financial_summary(
        current_user=current_user,
        preset=preset,
        start_date=start_date,
        end_date=end_date,
    )


@router.get(
    "/cash-flow",
    response_model=CashFlowSummaryResponse,
    status_code=status.HTTP_200_OK,
    summary="Flujo de Caja Real y Tesorería (Entradas vs Salidas)",
)
async def get_cash_flow(
    preset: Optional[DateRangePreset] = Query(DateRangePreset.THIS_MONTH, description="Rango predefinido de fechas"),
    start_date: Optional[datetime] = Query(None, description="Fecha de inicio personalizada"),
    end_date: Optional[datetime] = Query(None, description="Fecha de fin personalizada"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> CashFlowSummaryResponse:
    """Retorna el flujo de caja neto conciliando ventas de contado, cobranza y pagos a proveedores (RF-19)."""
    service = FinancialAnalyticsService(db)
    return await service.get_cash_flow_summary(
        current_user=current_user,
        preset=preset,
        start_date=start_date,
        end_date=end_date,
    )


@router.get(
    "/inventory-health",
    response_model=InventoryHealthResponse,
    status_code=status.HTTP_200_OK,
    summary="Diagnóstico de Inventario, Valuación y Rotación de Mercancía",
)
async def get_inventory_health(
    preset: Optional[DateRangePreset] = Query(DateRangePreset.THIS_MONTH, description="Rango predefinido de fechas"),
    start_date: Optional[datetime] = Query(None, description="Fecha de inicio personalizada"),
    end_date: Optional[datetime] = Query(None, description="Fecha de fin personalizada"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> InventoryHealthResponse:
    """Retorna la valuación total del inventario, top 10 productos vendidos y alertas de stock crítico (RF-20)."""
    service = FinancialAnalyticsService(db)
    return await service.get_inventory_health(
        current_user=current_user,
        preset=preset,
        start_date=start_date,
        end_date=end_date,
    )


@router.get(
    "/working-capital",
    response_model=WorkingCapitalResponse,
    status_code=status.HTTP_200_OK,
    summary="Capital de Trabajo y Posición Neta de Liquidez",
)
async def get_working_capital(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> WorkingCapitalResponse:
    """Retorna el balance de liquidez neta (Efectivo en caja + Cuentas por cobrar - Cuentas por pagar) (RF-21)."""
    service = FinancialAnalyticsService(db)
    return await service.get_working_capital(current_user=current_user)
