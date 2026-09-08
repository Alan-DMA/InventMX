# Importación del módulo decimal para cantidades de stock y costos
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de UUID para claves
import uuid
# Importación de constructores y funciones de SQLAlchemy
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

# Importación de modelos de dominio
from app.modules.inventory.domain.inventory_movement import (
    InventoryMovement,
    MovementType,
)


class MovementRepository:
    """
    Repositorio de acceso a datos para el Libro Mayor de Kardex (inventory_movements).
    Es un repositorio estrictamente append-only (solo inserción y consulta histórica).
    """

    def __init__(self, db: AsyncSession):
        # Asignación de la sesión de base de datos
        self.db = db

    async def record_movement(
        self,
        tenant_id: uuid.UUID,
        product_id: uuid.UUID,
        warehouse_id: uuid.UUID,
        movement_type: MovementType,
        quantity: Decimal,
        previous_stock: Decimal,
        new_stock: Decimal,
        unit_cost_mxn: Decimal = Decimal("0.00"),
        user_id: Optional[uuid.UUID] = None,
        from_warehouse_id: Optional[uuid.UUID] = None,
        to_warehouse_id: Optional[uuid.UUID] = None,
        reference_id: Optional[uuid.UUID] = None,
        notes: Optional[str] = None,
    ) -> InventoryMovement:
        """
        Registra un nuevo asiento inmutable en el Kardex de inventario.
        """
        movement = InventoryMovement(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            product_id=product_id,
            warehouse_id=warehouse_id,
            from_warehouse_id=from_warehouse_id,
            to_warehouse_id=to_warehouse_id,
            user_id=user_id,
            movement_type=movement_type,
            quantity=quantity,
            previous_stock=previous_stock,
            new_stock=new_stock,
            unit_cost_mxn=unit_cost_mxn,
            reference_id=reference_id,
            notes=notes,
        )
        self.db.add(movement)
        await self.db.flush()
        return movement

    async def list_movements(
        self,
        tenant_id: uuid.UUID,
        product_id: Optional[uuid.UUID] = None,
        warehouse_id: Optional[uuid.UUID] = None,
        movement_type: Optional[MovementType] = None,
        skip: int = 0,
        limit: int = 100,
    ) -> List[InventoryMovement]:
        """
        Retorna el historial de movimientos de inventario con carga de productos y almacenes.
        """
        stmt = (
            select(InventoryMovement)
            .where(InventoryMovement.tenant_id == tenant_id)
            .options(
                selectinload(InventoryMovement.product),
                selectinload(InventoryMovement.warehouse),
            )
            .order_by(InventoryMovement.created_at.desc())
        )

        if product_id is not None:
            stmt = stmt.where(InventoryMovement.product_id == product_id)

        if warehouse_id is not None:
            stmt = stmt.where(InventoryMovement.warehouse_id == warehouse_id)

        if movement_type is not None:
            stmt = stmt.where(InventoryMovement.movement_type == movement_type)

        stmt = stmt.offset(skip).limit(limit)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())
