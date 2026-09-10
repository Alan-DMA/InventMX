# Importación de marcas de fecha y tiempo
from datetime import datetime
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

# Importación del modelo de dominio de turnos y movimientos
from app.modules.sales_pos.domain.cash_movement import CashMovement
from app.modules.sales_pos.domain.cash_shift import CashShift, ShiftStatus


class CashShiftRepository:
    """
    Repositorio de persistencia asíncrona para Turnos de Caja (inventmx.cash_shifts) (RF-16, RF-17).
    Garantiza aislamiento multi-inquilino y operaciones de auditoría física.
    """
    def __init__(self, session: AsyncSession):
        # Sesión asíncrona de base de datos
        self.session = session

    async def create(self, shift: CashShift) -> CashShift:
        """
        Inserta un nuevo turno de caja en la base de datos.
        """
        self.session.add(shift)
        await self.session.flush()
        await self.session.refresh(shift)
        return shift

    async def get_active_shift_by_cashier(
        self,
        tenant_id: uuid.UUID,
        cashier_id: uuid.UUID,
    ) -> Optional[CashShift]:
        """
        Obtiene el turno actualmente abierto (status = OPEN) para un cajero específico.
        """
        stmt = (
            select(CashShift)
            .options(selectinload(CashShift.movements))
            .where(
                CashShift.tenant_id == tenant_id,
                CashShift.cashier_id == cashier_id,
                CashShift.status == ShiftStatus.OPEN,
            )
            .order_by(desc(CashShift.opened_at))
            .limit(1)
        )
        result = await self.session.execute(stmt)
        return result.scalars().first()

    async def get_by_id(
        self,
        tenant_id: uuid.UUID,
        shift_id: uuid.UUID,
    ) -> Optional[CashShift]:
        """
        Obtiene un turno de caja por su ID universal con sus movimientos asociados precargados.
        """
        stmt = (
            select(CashShift)
            .options(selectinload(CashShift.movements))
            .where(
                CashShift.id == shift_id,
                CashShift.tenant_id == tenant_id,
            )
        )
        result = await self.session.execute(stmt)
        return result.scalars().first()

    async def list_shifts(
        self,
        tenant_id: uuid.UUID,
        cashier_id: Optional[uuid.UUID] = None,
        status: Optional[ShiftStatus] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> List[CashShift]:
        """
        Lista el historial de turnos de caja con soporte de filtros por cajero, estado y rango de fechas.
        """
        stmt = (
            select(CashShift)
            .options(selectinload(CashShift.movements))
            .where(CashShift.tenant_id == tenant_id)
        )

        if cashier_id:
            stmt = stmt.where(CashShift.cashier_id == cashier_id)

        if status:
            stmt = stmt.where(CashShift.status == status)

        if start_date:
            stmt = stmt.where(CashShift.opened_at >= start_date)

        if end_date:
            stmt = stmt.where(CashShift.opened_at <= end_date)

        stmt = stmt.order_by(desc(CashShift.opened_at)).offset(offset).limit(limit)
        result = await self.session.execute(stmt)
        return list(result.scalars().all())

    async def update(self, shift: CashShift) -> CashShift:
        """
        Actualiza los datos de un turno de caja existente (cierre, conteo físico, diferencia).
        """
        self.session.add(shift)
        await self.session.flush()
        await self.session.refresh(shift)
        return shift
