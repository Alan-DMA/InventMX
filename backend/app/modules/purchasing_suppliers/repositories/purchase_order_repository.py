# Importación de tipado estático
from datetime import date
from typing import List, Optional, Tuple
# Importación de identificadores UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

# Importación de modelos de dominio
from app.modules.purchasing_suppliers.domain.purchase_order import (
    PurchaseOrder,
    PurchaseOrderItem,
    PurchaseOrderStatus,
)


class PurchaseOrderRepository:
    """
    Repositorio de persistencia para Órdenes de Compra a Proveedores.
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def generate_next_folio(self, tenant_id: uuid.UUID) -> str:
        """Genera el siguiente folio correlativo de compra (ej: OC-00001)."""
        stmt = select(func.count(PurchaseOrder.id)).where(PurchaseOrder.tenant_id == tenant_id)
        res = await self.session.execute(stmt)
        count = res.scalar() or 0
        return f"OC-{(count + 1):05d}"

    async def create(self, order: PurchaseOrder) -> PurchaseOrder:
        """Persiste una orden de compra e inserta sus renglones."""
        self.session.add(order)
        await self.session.flush()
        return order

    async def get_by_id(
        self,
        order_id: uuid.UUID,
        tenant_id: uuid.UUID,
        with_items: bool = True,
    ) -> Optional[PurchaseOrder]:
        """Obtiene una orden de compra por su ID con sus relaciones cargadas."""
        stmt = select(PurchaseOrder).where(
            PurchaseOrder.id == order_id,
            PurchaseOrder.tenant_id == tenant_id,
        )
        if with_items:
            stmt = stmt.options(
                selectinload(PurchaseOrder.items).selectinload(PurchaseOrderItem.product),
                selectinload(PurchaseOrder.supplier),
            )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_purchase_orders(
        self,
        tenant_id: uuid.UUID,
        supplier_id: Optional[uuid.UUID] = None,
        status: Optional[PurchaseOrderStatus] = None,
        date_from: Optional[date] = None,
        date_to: Optional[date] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[PurchaseOrder], int]:
        """Lista órdenes de compra con filtros y paginación."""
        base_query = select(PurchaseOrder).where(PurchaseOrder.tenant_id == tenant_id)
        count_query = select(func.count(PurchaseOrder.id)).where(PurchaseOrder.tenant_id == tenant_id)

        if supplier_id:
            base_query = base_query.where(PurchaseOrder.supplier_id == supplier_id)
            count_query = count_query.where(PurchaseOrder.supplier_id == supplier_id)

        if status:
            base_query = base_query.where(PurchaseOrder.status == status)
            count_query = count_query.where(PurchaseOrder.status == status)

        if date_from:
            base_query = base_query.where(func.date(PurchaseOrder.created_at) >= date_from)
            count_query = count_query.where(func.date(PurchaseOrder.created_at) >= date_from)

        if date_to:
            base_query = base_query.where(func.date(PurchaseOrder.created_at) <= date_to)
            count_query = count_query.where(func.date(PurchaseOrder.created_at) <= date_to)

        total_res = await self.session.execute(count_query)
        total = total_res.scalar() or 0

        stmt = (
            base_query.options(
                selectinload(PurchaseOrder.items).selectinload(PurchaseOrderItem.product),
                selectinload(PurchaseOrder.supplier),
            )
            .order_by(PurchaseOrder.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        res = await self.session.execute(stmt)
        return list(res.scalars().all()), total

    async def update(self, order: PurchaseOrder) -> PurchaseOrder:
        """Actualiza la orden de compra."""
        await self.session.flush()
        return order
