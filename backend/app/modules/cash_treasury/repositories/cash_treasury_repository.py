# Importación de fecha y hora
from datetime import datetime, timezone
# Importación de precisión decimal
from decimal import Decimal
# Importación de tipado estático
from typing import Any, Dict, List, Optional, Tuple
# Importación de identificadores UUID
import uuid

# Importación de componentes de SQLAlchemy
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

# Importación de modelos de base de datos
from app.modules.auth_tenancy.domain.user import User
from app.modules.cash_treasury.domain.cash_session_denomination import CashSessionDenomination
from app.modules.sales_pos.domain.cash_movement import CashMovement, CashMovementType
from app.modules.sales_pos.domain.cash_shift import CashShift, ShiftStatus
from app.modules.sales_pos.domain.payment import PaymentMethod, SalePayment
from app.modules.sales_pos.domain.sale import Sale, SaleStatus


class CashTreasuryRepository:
    """
    Repositorio de persistencia asíncrona para Tesorería y Arqueos de Caja.
    Maneja turnos (CashShift), movimientos menores (CashMovement) y desgloses
    físicos de denominaciones de Banxico (CashSessionDenomination).
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_shift_by_id(
        self,
        shift_id: uuid.UUID,
        tenant_id: Optional[uuid.UUID] = None,
    ) -> Optional[CashShift]:
        """Obtiene un turno por UUID con validación opcional de inquilino."""
        stmt = select(CashShift).where(CashShift.id == shift_id)
        if tenant_id:
            stmt = stmt.where(CashShift.tenant_id == tenant_id)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_active_shift_by_cashier(
        self,
        cashier_id: uuid.UUID,
        tenant_id: uuid.UUID,
    ) -> Optional[CashShift]:
        """Recupera la sesión actualmente abierta (status OPEN) para el cajero."""
        stmt = select(CashShift).where(
            CashShift.cashier_id == cashier_id,
            CashShift.tenant_id == tenant_id,
            CashShift.status == ShiftStatus.OPEN,
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def create_shift(self, shift: CashShift) -> CashShift:
        """Persiste una nueva sesión de caja."""
        self.session.add(shift)
        await self.session.flush()
        await self.session.refresh(shift)
        return shift

    async def update_shift(self, shift: CashShift) -> CashShift:
        """Actualiza y confirma los cambios de un turno de caja."""
        shift.updated_at = datetime.now(timezone.utc)
        await self.session.flush()
        return shift

    async def list_shifts(
        self,
        tenant_id: uuid.UUID,
        cashier_id: Optional[uuid.UUID] = None,
        status_filter: Optional[ShiftStatus] = None,
        date_from: Optional[datetime] = None,
        date_to: Optional[datetime] = None,
        limit: int = 20,
        offset: int = 0,
    ) -> Tuple[List[CashShift], int]:
        """Retorna el listado paginado de sesiones de caja con filtros."""
        query = select(CashShift).where(CashShift.tenant_id == tenant_id)

        if cashier_id:
            query = query.where(CashShift.cashier_id == cashier_id)
        if status_filter:
            query = query.where(CashShift.status == status_filter)
        if date_from:
            query = query.where(CashShift.opened_at >= date_from)
        if date_to:
            query = query.where(CashShift.opened_at <= date_to)

        count_stmt = select(func.count()).select_from(query.subquery())
        total = (await self.session.execute(count_stmt)).scalar() or 0

        stmt = query.order_by(CashShift.opened_at.desc()).limit(limit).offset(offset)
        result = await self.session.execute(stmt)
        return list(result.scalars().all()), total

    async def save_denominations(
        self,
        denominations: CashSessionDenomination,
    ) -> CashSessionDenomination:
        """Persiste el conteo de billetes y monedas de Banxico."""
        self.session.add(denominations)
        await self.session.flush()
        await self.session.refresh(denominations)
        return denominations

    async def get_denominations(
        self,
        shift_id: uuid.UUID,
        is_opening: bool,
    ) -> Optional[CashSessionDenomination]:
        """Recupera el conteo de billetes de apertura o cierre."""
        stmt = select(CashSessionDenomination).where(
            CashSessionDenomination.shift_id == shift_id,
            CashSessionDenomination.is_opening == is_opening,
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def create_cash_movement(self, movement: CashMovement) -> CashMovement:
        """Persiste un movimiento manual de caja menor (salida o entrada)."""
        self.session.add(movement)
        await self.session.flush()
        await self.session.refresh(movement)
        return movement

    async def list_movements(
        self,
        shift_id: uuid.UUID,
        limit: int = 50,
        offset: int = 0,
    ) -> List[CashMovement]:
        """Lista los retiros o depósitos registrados en el turno."""
        stmt = (
            select(CashMovement)
            .where(CashMovement.shift_id == shift_id)
            .order_by(CashMovement.created_at.asc())
            .limit(limit)
            .offset(offset)
        )
        result = await self.session.execute(stmt)
        return list(result.scalars().all())

    async def get_shift_sales_cash_total(
        self,
        tenant_id: uuid.UUID,
        cashier_id: uuid.UUID,
        opened_at: datetime,
        closed_at: Optional[datetime] = None,
    ) -> Tuple[Decimal, int]:
        """
        Calcula el total de efectivo neto cobrado en ventas durante el periodo del turno.
        Retorna (total_efectivo_mxn, cantidad_ventas_efectivo).
        """
        end_time = closed_at or datetime.now(timezone.utc)
        stmt = (
            select(
                func.coalesce(func.sum(SalePayment.amount_paid_mxn - SalePayment.change_returned_mxn), Decimal("0.00")),
                func.count(func.distinct(Sale.id)),
            )
            .select_from(SalePayment)
            .join(Sale, SalePayment.sale_id == Sale.id)
            .where(
                Sale.tenant_id == tenant_id,
                Sale.cashier_id == cashier_id,
                Sale.status == SaleStatus.COMPLETED,
                Sale.created_at >= opened_at,
                Sale.created_at <= end_time,
                SalePayment.payment_method == PaymentMethod.CASH_MXN,
            )
        )
        result = await self.session.execute(stmt)
        row = result.one()
        return Decimal(str(row[0])), int(row[1])

    async def get_shift_movements_net_mxn(
        self,
        shift_id: uuid.UUID,
    ) -> Decimal:
        """
        Calcula el neto de movimientos manuales de caja:
        (Suma de CASH_IN / DEPOSIT) - (Suma de CASH_OUT / WITHDRAWAL).
        """
        stmt_in = select(func.coalesce(func.sum(CashMovement.amount_mxn), Decimal("0.00"))).where(
            CashMovement.shift_id == shift_id,
            CashMovement.movement_type == CashMovementType.CASH_IN,
        )
        total_in = (await self.session.execute(stmt_in)).scalar() or Decimal("0.00")

        stmt_out = select(func.coalesce(func.sum(CashMovement.amount_mxn), Decimal("0.00"))).where(
            CashMovement.shift_id == shift_id,
            CashMovement.movement_type == CashMovementType.CASH_OUT,
        )
        total_out = (await self.session.execute(stmt_out)).scalar() or Decimal("0.00")

        return Decimal(str(total_in)) - Decimal(str(total_out))
