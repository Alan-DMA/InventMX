# Importación del módulo datetime
from datetime import datetime, time, timedelta
# Importación de tipado estático
from typing import Optional
import uuid

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
    SalesTrendsResponse,
    WorkingCapitalResponse,
)
from app.modules.analytics_reports.services.financial_analytics_service import FinancialAnalyticsService

# Router del Módulo de Finanzas y Analítica
router = APIRouter(prefix="/analytics", tags=["Finance & Analytics"])


@router.get(
    "/dashboard",
    status_code=status.HTTP_200_OK,
    summary="Dashboard principal con KPIs del negocio (Canonical OpenAPI /analytics/dashboard)",
    description="Retorna los indicadores clave de rendimiento (KPIs) para el dashboard principal calculados en tiempo real.",
)
async def get_dashboard_kpis(
    period: Optional[str] = Query("TODAY", description="Periodo (TODAY, YESTERDAY, WEEK, MONTH, CUSTOM)"),
    date_from: Optional[datetime] = Query(None, description="Fecha de inicio para CUSTOM"),
    date_to: Optional[datetime] = Query(None, description="Fecha de fin para CUSTOM"),
    compare_previous: bool = Query(True, description="Incluir comparación con periodo anterior"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Endpoint canónico formal de KPIs del Dashboard (OpenAPI docs/api/analytics.yaml).
    Calcula métricas de venta hoy vs ayer, margen, inventario y alertas en vivo.
    """
    # Instanciar servicio financiero y de analítica
    service = FinancialAnalyticsService(db)
    # Obtener KPIs consolidados de la base de datos
    kpis = await service.get_dashboard_kpis(
        current_user=current_user,
        period=period or "TODAY",
        date_from=date_from,
        date_to=date_to,
        compare_previous=compare_previous,
    )
    # Serializar en diccionario Pydantic v2
    kpis_dict = kpis.model_dump(mode="json")
    # Retornar estructura híbrida que satisface el formato OpenAPI (data) y el formato directo
    return {
        "success": True,
        "data": kpis_dict,
        **kpis_dict,
    }


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
    "/sales-trends",
    response_model=SalesTrendsResponse,
    status_code=status.HTTP_200_OK,
    summary="Serie Diaria de Ventas del Periodo (Ingreso neto, tickets y utilidad por día)",
)
async def get_sales_trends(
    preset: Optional[DateRangePreset] = Query(DateRangePreset.THIS_MONTH, description="Rango predefinido de fechas"),
    start_date: Optional[datetime] = Query(None, description="Fecha de inicio personalizada"),
    end_date: Optional[datetime] = Query(None, description="Fecha de fin personalizada"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> SalesTrendsResponse:
    """Alimenta la gráfica diaria del dashboard de Reportes; misma base que `/financial-summary` (RF-21)."""
    service = FinancialAnalyticsService(db)
    return await service.get_sales_trends(
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


@router.get(
    "/commissions",
    status_code=status.HTTP_200_OK,
    summary="Mis comisiones (RF-10 / SR-05) — sólo del usuario en sesión",
    description=(
        "Comisiones devengadas por el usuario autenticado en el periodo, con desglose diario e histórico "
        "de los últimos 6 meses. Nunca expone las comisiones de otros empleados (dato privado de cada "
        "vendedor). Sin filtros de fecha se usa el mes en curso; `period_month=YYYY-MM` acota a ese mes."
    ),
)
async def get_analytics_commissions(
    period_month: Optional[str] = Query(None, description="Mes en formato YYYY-MM", pattern=r"^\d{4}-(0[1-9]|1[0-2])$"),
    start_date: Optional[datetime] = Query(None, description="Fecha de inicio"),
    end_date: Optional[datetime] = Query(None, description="Fecha de fin"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Tablero personal de comisiones. Regla Constitucional: Artículo VIII (8.2).
    """
    from app.modules.sales_pos.services.sales_service import SalesService
    sales_service = SalesService(db)

    # Resolver el periodo: mes explícito > rango explícito > mes en curso.
    if period_month:
        year, month = (int(p) for p in period_month.split("-"))
        start_date = datetime(year, month, 1)
        end_date = (datetime(year + 1, 1, 1) if month == 12 else datetime(year, month + 1, 1)) - timedelta(microseconds=1)
    elif not (start_date and end_date):
        now = datetime.now()
        start_date = datetime(now.year, now.month, 1)
        end_date = datetime.combine(now.date(), time.max)
    period_label = start_date.strftime("%Y-%m")

    # Siempre filtrado al usuario en sesión: las comisiones ajenas no se exponen.
    summary = await sales_service.get_commissions_summary(
        current_user=current_user,
        user_id=current_user.id,
        start_date=start_date,
        end_date=end_date,
    )
    mine = next((s for s in summary.summaries_by_user if s.user_id == current_user.id), None)

    daily = await sales_service.commission_repo.get_daily_breakdown(
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        start_date=start_date,
        end_date=end_date,
    )
    history = await sales_service.commission_repo.get_monthly_history(
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        months=6,
    )

    return {
        "period": period_label,
        "period_start": start_date,
        "period_end": end_date,
        "current_user": {
            "cashier_id": str(current_user.id),
            "cashier_name": current_user.full_name or current_user.email,
            "role": current_user.role.name if current_user.role else None,
            "commission_type": current_user.commission_type.value,
            "commission_rate": current_user.commission_rate,
        },
        "summary": {
            "sales_count": mine.total_sales_count if mine else 0,
            "total_sales_mxn": mine.total_sales_amount_mxn if mine else 0,
            "earned_commission_mxn": mine.total_commission_amount_mxn if mine else 0,
            "pending_settlement_mxn": mine.pending_settlement_mxn if mine else 0,
        },
        "daily_breakdown": [
            {
                "date": d.date.isoformat(),
                "sales_count": d.sales_count,
                "sales_amount_mxn": d.sales_amount_mxn,
                "commission_mxn": d.commission_mxn,
            }
            for d in daily
        ],
        "history": history,
    }
