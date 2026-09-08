# Importación del módulo datetime para marcas y comparaciones de expiración
from datetime import datetime, timezone
# Importación del módulo decimal para precisión en cantidades
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de UUID para claves
import uuid
# Importación de constructores y funciones de SQLAlchemy
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

# Importación del modelo de dominio StockReservation y su Enum
from app.modules.inventory.domain.stock_reservation import (
    ReservationStatus,
    StockReservation,
)


class ReservationRepository:
    """
    Repositorio de acceso a datos para la gestión de apartados de stock con TTL (RF-06).
    Controla la creación, consulta y expiración de reservas.
    """

    def __init__(self, db: AsyncSession):
        # Asignación de la sesión asíncrona de base de datos
        self.db = db

    async def get_by_id(self, reservation_id: uuid.UUID) -> Optional[StockReservation]:
        """
        Obtiene un apartado por su identificador único UUID.
        """
        stmt = (
            select(StockReservation)
            .where(StockReservation.id == reservation_id)
            .options(
                selectinload(StockReservation.product),
                selectinload(StockReservation.warehouse),
            )
            .execution_options(populate_existing=True)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_expired_pending(self, now_utc: Optional[datetime] = None) -> List[StockReservation]:
        """
        Obtiene todos los apartados en estado PENDING cuya fecha de expiración ya fue superada.
        """
        current_time = now_utc or datetime.now(timezone.utc)
        stmt = (
            select(StockReservation)
            .where(
                StockReservation.status == ReservationStatus.PENDING,
                StockReservation.expires_at <= current_time,
            )
            .options(
                selectinload(StockReservation.product),
                selectinload(StockReservation.warehouse),
            )
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def create(
        self,
        tenant_id: uuid.UUID,
        product_id: uuid.UUID,
        warehouse_id: uuid.UUID,
        quantity: Decimal,
        expires_at: datetime,
        reference_id: Optional[uuid.UUID] = None,
    ) -> StockReservation:
        """
        Crea e inserta un nuevo registro de apartado de existencias con fecha de expiración.
        """
        reservation = StockReservation(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            product_id=product_id,
            warehouse_id=warehouse_id,
            quantity=quantity,
            status=ReservationStatus.PENDING,
            reference_id=reference_id,
            expires_at=expires_at,
        )
        self.db.add(reservation)
        await self.db.flush()
        return reservation

    async def update_status(
        self, reservation: StockReservation, new_status: ReservationStatus
    ) -> StockReservation:
        """
        Actualiza el estado de vigencia de una reserva.
        """
        reservation.status = new_status
        await self.db.flush()
        return reservation
