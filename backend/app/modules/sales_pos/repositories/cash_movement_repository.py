# Importación de marcas de fecha y tiempo
from datetime import datetime
# Importación de precisión decimal
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional, Tuple
# Importación de identificadores UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación del modelo de dominio de movimientos de caja
from app.modules.sales_pos.domain.cash_movement import (
    CashMovement,
    CashMovementType,
)


class CashMovementRepository:
    """
    Repositorio de persistencia asíncrona para Movimientos Manuales de Efectivo (inventmx.cash_movements) (RF-16).
    Gestiona el registro de aportaciones (CASH_IN) y retiros/gastos (CASH_OUT) de caja chica.
    """
    def __init__(self, session: AsyncSession):
        # Sesión asíncrona de base de datos
        self.session = session

    async def create(self, movement: CashMovement) -> CashMovement:
        """
        Inserta un nuevo movimiento manual de efectivo en la base de datos.
        """
        self.session.add(movement)
        await self.session.flush()
        await self.session.refresh(movement)
        return movement

    async def list_by_shift(
        self,
        tenant_id: uuid.UUID,
        shift_id: uuid.UUID,
    ) -> List[CashMovement]:
        """
        Lista todos los movimientos manuales registrados dentro de un turno específico.
        """
        stmt = (
            select(CashMovement)
            .where(
                CashMovement.tenant_id == tenant_id,
                CashMovement.shift_id == shift_id,
            )
            .order_by(desc(CashMovement.created_at))
        )
        result = await self.session.execute(stmt)
        return list(result.scalars().all())

    async def get_shift_movement_totals(
        self,
        tenant_id: uuid.UUID,
        shift_id: uuid.UUID,
    ) -> Tuple[Decimal, Decimal]:
        """
        Calcula de forma agregada el total de entradas (CASH_IN) y salidas (CASH_OUT) del turno.
        Retorna una tupla: (total_cash_in_mxn, total_cash_out_mxn).
        """
        stmt_in = select(func.coalesce(func.sum(CashMovement.amount_mxn), Decimal("0.00"))).where(
            CashMovement.tenant_id == tenant_id,
            CashMovement.shift_id == shift_id,
            CashMovement.movement_type == CashMovementType.CASH_IN,
        )
        stmt_out = select(func.coalesce(func.sum(CashMovement.amount_mxn), Decimal("0.00"))).where(
            CashMovement.tenant_id == tenant_id,
            CashMovement.shift_id == shift_id,
            CashMovement.movement_type == CashMovementType.CASH_OUT,
        )

        res_in = await self.session.execute(stmt_in)
        res_out = await self.session.execute(stmt_out)

        total_in = Decimal(str(res_in.scalar() or Decimal("0.00")))
        total_out = Decimal(str(res_out.scalar() or Decimal("0.00")))

        return total_in, total_out
