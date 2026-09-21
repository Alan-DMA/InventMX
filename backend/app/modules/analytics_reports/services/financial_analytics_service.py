# Importación de precisión decimal para Pesos Mexicanos
from datetime import datetime, time, timedelta, timezone
from decimal import Decimal
# Importación de tipado estático
from typing import Any, Dict, List, Optional, Tuple
# Importación de identificadores UUID
import uuid

# Importación de SQLAlchemy
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de entidades de dominio
from app.modules.auth_tenancy.domain.user import User
from app.modules.analytics_reports.repositories.financial_analytics_repository import FinancialAnalyticsRepository
from app.modules.analytics_reports.schemas.analytics_schemas import (
    CashFlowSummaryResponse,
    DailySalesPointResponse,
    CriticalStockProductResponse,
    DateRangePreset,
    ExecutiveFinancialSummaryResponse,
    InventoryHealthResponse,
    InventoryValuationResponse,
    PaymentMethodMetric,
    SalesTrendsResponse,
    TopSellingProductResponse,
    WorkingCapitalResponse,
)


class FinancialAnalyticsService:
    """
    Servicio de inteligencia de negocios, analítica financiera y salud operativa (RF-18 a RF-22 / Const. Art. 7.6).
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repo = FinancialAnalyticsRepository(session)

    def resolve_date_range(
        self,
        preset: Optional[DateRangePreset] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> Tuple[datetime, datetime]:
        """Resuelve un rango de fechas a partir de un preset o fechas explícitas."""
        now = datetime.now()

        if preset == DateRangePreset.TODAY:
            start = datetime.combine(now.date(), time.min)
            end = datetime.combine(now.date(), time.max)
        elif preset == DateRangePreset.THIS_WEEK:
            start_week = now.date() - timedelta(days=now.weekday())
            start = datetime.combine(start_week, time.min)
            end = datetime.combine(now.date() + timedelta(days=(6 - now.weekday())), time.max)
        elif preset == DateRangePreset.THIS_MONTH:
            start = datetime.combine(now.date().replace(day=1), time.min)
            # Fin de mes
            next_month = (now.date().replace(day=28) + timedelta(days=4)).replace(day=1)
            end = datetime.combine(next_month - timedelta(days=1), time.max)
        elif preset == DateRangePreset.LAST_MONTH:
            first_this_month = now.date().replace(day=1)
            last_day_prev = first_this_month - timedelta(days=1)
            start = datetime.combine(last_day_prev.replace(day=1), time.min)
            end = datetime.combine(last_day_prev, time.max)
        elif start_date and end_date:
            start = start_date
            end = end_date
        else:
            # Por defecto: mes en curso
            start = datetime.combine(now.date().replace(day=1), time.min)
            end = datetime.combine(now.date(), time.max)

        return start, end

    async def get_executive_financial_summary(
        self,
        current_user: User,
        preset: Optional[DateRangePreset] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> ExecutiveFinancialSummaryResponse:
        """Genera el resumen financiero ejecutivo con COGS y margen de rentabilidad (RF-18)."""
        start, end = self.resolve_date_range(preset, start_date, end_date)
        metrics = await self.repo.get_financial_summary_metrics(current_user.tenant_id, start, end)

        breakdown_data = await self.repo.get_payment_methods_breakdown(
            current_user.tenant_id,
            start,
            end,
            metrics["net_sales_mxn"],
        )
        payment_methods = [PaymentMethodMetric(**b) for b in breakdown_data]

        return ExecutiveFinancialSummaryResponse(
            period_start=start,
            period_end=end,
            gross_sales_mxn=metrics["gross_sales_mxn"],
            discounts_mxn=metrics["discounts_mxn"],
            net_sales_mxn=metrics["net_sales_mxn"],
            refunds_mxn=metrics["refunds_mxn"],
            cogs_mxn=metrics["cogs_mxn"],
            gross_profit_mxn=metrics["gross_profit_mxn"],
            profit_margin_pct=metrics["profit_margin_pct"],
            average_ticket_mxn=metrics["average_ticket_mxn"],
            total_transactions=int(metrics["total_transactions"]),
            payment_methods=payment_methods,
        )

    async def get_cash_flow_summary(
        self,
        current_user: User,
        preset: Optional[DateRangePreset] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> CashFlowSummaryResponse:
        """Genera la conciliación de flujo de caja real y tesorería (RF-19)."""
        start, end = self.resolve_date_range(preset, start_date, end_date)
        cf = await self.repo.get_cash_flow_metrics(current_user.tenant_id, start, end)

        return CashFlowSummaryResponse(
            period_start=start,
            period_end=end,
            cash_sales_inflow_mxn=cf["cash_sales_inflow_mxn"],
            credit_collections_inflow_mxn=cf["credit_collections_inflow_mxn"],
            cash_income_movements_mxn=cf["cash_income_movements_mxn"],
            total_inflow_mxn=cf["total_inflow_mxn"],
            supplier_payments_outflow_mxn=cf["supplier_payments_outflow_mxn"],
            cash_expense_movements_mxn=cf["cash_expense_movements_mxn"],
            total_outflow_mxn=cf["total_outflow_mxn"],
            net_cash_flow_mxn=cf["net_cash_flow_mxn"],
        )

    async def get_inventory_health(
        self,
        current_user: User,
        preset: Optional[DateRangePreset] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> InventoryHealthResponse:
        """Genera el diagnóstico consolidado de inventario, valuación y rotación (RF-20)."""
        start, end = self.resolve_date_range(preset, start_date, end_date)
        val_data = await self.repo.get_inventory_valuation(current_user.tenant_id)
        top_data = await self.repo.get_top_selling_products(current_user.tenant_id, start, end, limit=10)
        crit_data = await self.repo.get_critical_stock_products(current_user.tenant_id)

        valuation = InventoryValuationResponse(**val_data)
        top_products = [TopSellingProductResponse(**t) for t in top_data]
        critical_products = [CriticalStockProductResponse(**c) for c in crit_data]

        return InventoryHealthResponse(
            valuation=valuation,
            top_selling_products=top_products,
            critical_stock_products=critical_products,
        )

    async def get_sales_trends(
        self,
        current_user: User,
        preset: Optional[DateRangePreset] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> SalesTrendsResponse:
        """Serie diaria de ventas del periodo, con los días sin venta en cero (RF-21)."""
        start, end = self.resolve_date_range(preset, start_date, end_date)
        by_day = await self.repo.get_daily_sales_series(current_user.tenant_id, start, end)

        # Un punto por día natural del rango: "no vendí" ($0) es distinto de "sin dato".
        # Los presets de calendario terminan en el futuro (fin de semana/mes); la
        # serie se corta en hoy para no pintar días que aún no ocurren.
        last_day = min(end.date(), datetime.now().date())
        points: List[DailySalesPointResponse] = []
        cursor = start.date()
        while cursor <= last_day:
            metrics = by_day.get(cursor)
            points.append(
                DailySalesPointResponse(
                    period=cursor,
                    revenue_mxn=metrics["revenue_mxn"] if metrics else Decimal("0.00"),
                    orders_count=metrics["orders_count"] if metrics else 0,
                    gross_profit_mxn=metrics["gross_profit_mxn"] if metrics else Decimal("0.00"),
                )
            )
            cursor += timedelta(days=1)

        return SalesTrendsResponse(period_start=start, period_end=end, granularity="daily", trends=points)

    async def get_working_capital(
        self,
        current_user: User,
    ) -> WorkingCapitalResponse:
        """Calcula la posición de capital de trabajo y liquidez operativa neta (RF-21)."""
        wc = await self.repo.get_working_capital_metrics(current_user.tenant_id)

        return WorkingCapitalResponse(
            as_of_date=datetime.now(),
            cash_in_register_mxn=wc["cash_in_register_mxn"],
            accounts_receivable_mxn=wc["accounts_receivable_mxn"],
            accounts_payable_mxn=wc["accounts_payable_mxn"],
            net_working_capital_mxn=wc["net_working_capital_mxn"],
        )
