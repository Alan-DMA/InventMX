# Importación del módulo datetime
from datetime import datetime
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
    summary="Reporte de Comisiones de Vendedores (Canonical OpenAPI /analytics/commissions)",
    description="Calcula y retorna las comisiones devengadas por vendedores/cajeros en el periodo especificado.",
)
async def get_analytics_commissions(
    cashier_id: Optional[uuid.UUID] = Query(None, description="Filtrar por cajero específico"),
    user_id: Optional[uuid.UUID] = Query(None, description="Filtrar por usuario específico"),
    cashier_name: Optional[str] = Query(None, description="Filtrar por nombre de cajero"),
    period_month: Optional[str] = Query(None, description="Mes en formato YYYY-MM"),
    start_date: Optional[datetime] = Query(None, description="Fecha de inicio"),
    end_date: Optional[datetime] = Query(None, description="Fecha de fin"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Endpoint formal para consulta de comisiones en el módulo de analítica.
    Regla Constitucional: Artículo VIII (8.2), OpenAPI docs/api/analytics.yaml.
    """
    from app.modules.sales_pos.services.sales_service import SalesService
    sales_service = SalesService(db)

    target_id = cashier_id or user_id
    summary = await sales_service.get_commissions_summary(
        current_user=current_user,
        user_id=target_id,
        start_date=start_date,
        end_date=end_date,
    )

    # Construir respuesta híbrida que satisface tanto la OpenAPI spec como el repositorio de Flutter
    ranking = [
        {
            "cashier_name": s.user_name,
            "commission_mxn": float(s.total_commission_amount_mxn),
            "is_current_user": str(s.user_id) == str(current_user.id),
        }
        for s in summary.summaries_by_user
    ]

    return {
        "period": period_month or datetime.now().strftime("%Y-%m"),
        "total_commissions_mxn": summary.total_commissions_mxn,
        "total_sales_count": summary.total_sales_count,
        "cashiers": [
            {
                "cashier_id": str(s.user_id),
                "cashier_name": s.user_name,
                "total_sales_mxn": s.total_sales_amount_mxn,
                "earned_commission_mxn": s.total_commission_amount_mxn,
                "sales_count": s.total_sales_count,
            }
            for s in summary.summaries_by_user
        ],
        "ranking": ranking,
        "summaries_by_user": summary.summaries_by_user,
    }

