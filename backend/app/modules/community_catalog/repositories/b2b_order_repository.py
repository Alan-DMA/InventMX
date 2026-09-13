# Importación de precisión decimal para Pesos Mexicanos
from datetime import datetime
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid

# Importación de constructs de SQLAlchemy
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de entidades de dominio
from app.modules.community_catalog.domain.b2b_order import (
    B2BOrder,
    B2BOrderItem,
    B2BOrderStatus,
)


class B2BOrderRepository:
    """
    Repositorio de acceso a datos para transacciones de pedidos B2B entre comercios (RF-27).
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create_order(self, order: B2BOrder) -> B2BOrder:
        """Persiste un nuevo pedido mayorista y sus renglones."""
        self.session.add(order)
        await self.session.flush()
        await self.session.refresh(order)
        return order

    async def get_order_by_id(self, order_id: uuid.UUID) -> Optional[B2BOrder]:
        """Obtiene un pedido B2B por su ID primario."""
        stmt = select(B2BOrder).where(B2BOrder.id == order_id)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_sent_orders(
        self,
        buyer_tenant_id: uuid.UUID,
        status: Optional[B2BOrderStatus] = None,
    ) -> List[B2BOrder]:
        """Retorna los pedidos mayoristas emitidos por el comercio como comprador."""
        stmt = select(B2BOrder).where(B2BOrder.buyer_tenant_id == buyer_tenant_id)
        if status:
            stmt = stmt.where(B2BOrder.status == status)
        stmt = stmt.order_by(B2BOrder.created_at.desc())
        result = await self.session.execute(stmt)
        return list(result.scalars().unique().all())

    async def list_received_orders(
        self,
        seller_tenant_id: uuid.UUID,
        status: Optional[B2BOrderStatus] = None,
    ) -> List[B2BOrder]:
        """Retorna los pedidos mayoristas recibidos por el comercio como vendedor."""
        stmt = select(B2BOrder).where(B2BOrder.seller_tenant_id == seller_tenant_id)
        if status:
            stmt = stmt.where(B2BOrder.status == status)
        stmt = stmt.order_by(B2BOrder.created_at.desc())
        result = await self.session.execute(stmt)
        return list(result.scalars().unique().all())

    async def generate_next_order_number(self) -> str:
        """Genera un folio consecutivo legible para pedidos B2B (ej: B2B-2026-0001)."""
        year = datetime.now().year
        prefix = f"B2B-{year}-"
        stmt = select(func.count(B2BOrder.id))
        count = (await self.session.execute(stmt)).scalar() or 0
        return f"{prefix}{count + 1:04d}"
