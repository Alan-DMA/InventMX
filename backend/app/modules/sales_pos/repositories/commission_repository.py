# Importación de precisión decimal
from decimal import Decimal
# Importación de marcas de tiempo
from datetime import date, datetime
# Importación de tipado estático
from typing import Any, Dict, List, Optional
# Importación de identificadores UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

# Importación de modelos y esquemas
from app.modules.auth_tenancy.domain.user import User
from app.modules.sales_pos.domain.commission import SaleCommission
from app.modules.sales_pos.domain.sale import Sale, SaleStatus
from app.modules.sales_pos.schemas.commission import DailyCommissionEntry, UserCommissionSummary


def _sale_still_counts():
    """
    Una comisión sigue valiendo mientras la venta no se cancele ni se devuelva por
    completo. El asiento no se toca (es inmutable); se filtra al leer.
    """
    return (
        Sale.status != SaleStatus.CANCELLED,
        Sale.refunded_amount_mxn < Sale.total_mxn,
    )


class CommissionRepository:
    """
    Repositorio de persistencia asíncrona para comisiones dinámicas de venta (RF-10 / Const. Art. 8.2).
    """
    def __init__(self, session: AsyncSession):
        # Sesión asíncrona de base de datos
        self.session = session

    async def create_commission(self, commission: SaleCommission) -> SaleCommission:
        """
        Inserta un nuevo asiento de comisión inmutable vinculado a una venta.
        """
        self.session.add(commission)
        await self.session.flush()
        return commission

    async def get_by_sale_id(self, sale_id: uuid.UUID, tenant_id: uuid.UUID) -> List[SaleCommission]:
        """
        Recupera las comisiones registradas para una venta específica bajo aislamiento RLS.
        """
        query = (
            select(SaleCommission)
            .options(selectinload(SaleCommission.user))
            .where(SaleCommission.sale_id == sale_id)
            .where(SaleCommission.tenant_id == tenant_id)
            .order_by(SaleCommission.created_at.asc())
        )
        result = await self.session.execute(query)
        return list(result.scalars().all())

    async def get_commissions_by_period(
        self,
        tenant_id: uuid.UUID,
        user_id: Optional[uuid.UUID] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> List[SaleCommission]:
        """
        Consulta listado de comisiones filtrado por empleado y rango de fechas.
        """
        query = (
            select(SaleCommission)
            .options(selectinload(SaleCommission.user))
            .where(SaleCommission.tenant_id == tenant_id)
        )
        if user_id:
            query = query.where(SaleCommission.user_id == user_id)
        if start_date:
            query = query.where(SaleCommission.created_at >= start_date)
        if end_date:
            query = query.where(SaleCommission.created_at <= end_date)

        query = query.order_by(SaleCommission.created_at.desc())
        result = await self.session.execute(query)
        return list(result.scalars().all())

    async def get_summary_by_users(
        self,
        tenant_id: uuid.UUID,
        user_id: Optional[uuid.UUID] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> List[UserCommissionSummary]:
        """
        Calcula resumen agregado de comisiones agrupado por vendedor/cajero.
        """
        # Consulta base de usuarios
        u_query = select(User).where(User.tenant_id == tenant_id)
        if user_id:
            u_query = u_query.where(User.id == user_id)

        u_res = await self.session.execute(u_query)
        users = list(u_res.scalars().all())

        summaries: List[UserCommissionSummary] = []

        for u in users:
            c_query = (
                select(SaleCommission)
                .join(Sale, Sale.id == SaleCommission.sale_id)
                .where(SaleCommission.tenant_id == tenant_id)
                .where(SaleCommission.user_id == u.id)
                .where(*_sale_still_counts())
            )
            if start_date:
                c_query = c_query.where(SaleCommission.created_at >= start_date)
            if end_date:
                c_query = c_query.where(SaleCommission.created_at <= end_date)

            c_res = await self.session.execute(c_query)
            commissions = list(c_res.scalars().all())

            total_sales_count = len(commissions)
            total_sales_amount = sum((c.base_amount_mxn for c in commissions), Decimal("0.00"))
            total_comm_amount = sum((c.commission_amount_mxn for c in commissions), Decimal("0.00"))
            pending_settled = sum((c.commission_amount_mxn for c in commissions if not c.is_settled), Decimal("0.00"))
            settled_amount = sum((c.commission_amount_mxn for c in commissions if c.is_settled), Decimal("0.00"))

            # Solo incluir si tiene ventas o si se filtró por ese usuario específico
            if total_sales_count > 0 or user_id is not None:
                summaries.append(
                    UserCommissionSummary(
                        user_id=u.id,
                        user_name=u.full_name or u.email,
                        user_email=u.email,
                        total_sales_count=total_sales_count,
                        total_sales_amount_mxn=total_sales_amount.quantize(Decimal("0.01")),
                        total_commission_amount_mxn=total_comm_amount.quantize(Decimal("0.01")),
                        pending_settlement_mxn=pending_settled.quantize(Decimal("0.01")),
                        settled_commission_mxn=settled_amount.quantize(Decimal("0.01")),
                        commission_type=u.commission_type,
                        commission_rate=u.commission_rate,
                    )
                )

        return summaries

    async def get_daily_breakdown(
        self,
        tenant_id: uuid.UUID,
        user_id: uuid.UUID,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> List[DailyCommissionEntry]:
        """
        Comisión devengada por día natural para un empleado (SR-05: desglose diario del tablero).
        """
        day = func.date(SaleCommission.created_at)
        query = (
            select(
                day.label("day"),
                func.count(SaleCommission.id).label("sales_count"),
                func.coalesce(func.sum(SaleCommission.base_amount_mxn), Decimal("0.00")).label("sales_amount_mxn"),
                func.coalesce(func.sum(SaleCommission.commission_amount_mxn), Decimal("0.00")).label("commission_mxn"),
            )
            .join(Sale, Sale.id == SaleCommission.sale_id)
            .where(SaleCommission.tenant_id == tenant_id)
            .where(SaleCommission.user_id == user_id)
            .where(*_sale_still_counts())
        )
        if start_date:
            query = query.where(SaleCommission.created_at >= start_date)
        if end_date:
            query = query.where(SaleCommission.created_at <= end_date)
        query = query.group_by(day).order_by(day.desc())

        result = await self.session.execute(query)
        return [
            DailyCommissionEntry(
                date=r.day,
                sales_count=int(r.sales_count),
                sales_amount_mxn=Decimal(str(r.sales_amount_mxn)).quantize(Decimal("0.01")),
                commission_mxn=Decimal(str(r.commission_mxn)).quantize(Decimal("0.01")),
            )
            for r in result.all()
        ]

    async def get_monthly_history(
        self,
        tenant_id: uuid.UUID,
        user_id: uuid.UUID,
        months: int = 6,
        now: Optional[datetime] = None,
    ) -> List[Dict[str, Any]]:
        """
        Comisión devengada por mes natural del empleado en los últimos `months` meses
        (el actual incluido). Los meses sin ventas vienen en cero, del más reciente al más viejo.
        """
        now = now or datetime.now()
        # Primer día del mes más antiguo del recorte
        first_year, first_month = now.year, now.month - (months - 1)
        while first_month <= 0:
            first_month += 12
            first_year -= 1
        window_start = datetime(first_year, first_month, 1)

        month_col = func.date_trunc("month", SaleCommission.created_at)
        query = (
            select(
                month_col.label("month"),
                func.count(SaleCommission.id).label("sales_count"),
                func.coalesce(func.sum(SaleCommission.base_amount_mxn), Decimal("0.00")).label("sales_amount_mxn"),
                func.coalesce(func.sum(SaleCommission.commission_amount_mxn), Decimal("0.00")).label("commission_mxn"),
            )
            .join(Sale, Sale.id == SaleCommission.sale_id)
            .where(SaleCommission.tenant_id == tenant_id)
            .where(SaleCommission.user_id == user_id)
            .where(SaleCommission.created_at >= window_start)
            .where(*_sale_still_counts())
            .group_by(month_col)
        )
        result = await self.session.execute(query)
        by_month = {(r.month.year, r.month.month): r for r in result.all()}

        history: List[Dict[str, Any]] = []
        year, month = now.year, now.month
        for _ in range(months):
            row = by_month.get((year, month))
            history.append({
                "month": f"{year:04d}-{month:02d}",
                "sales_count": int(row.sales_count) if row else 0,
                "sales_amount_mxn": Decimal(str(row.sales_amount_mxn)).quantize(Decimal("0.01")) if row else Decimal("0.00"),
                "commission_mxn": Decimal(str(row.commission_mxn)).quantize(Decimal("0.01")) if row else Decimal("0.00"),
            })
            month -= 1
            if month == 0:
                month, year = 12, year - 1
        return history
