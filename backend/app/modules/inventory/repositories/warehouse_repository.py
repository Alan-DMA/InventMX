# Importación de UUID para identificación única
import uuid
# Importación de tipado estático
from typing import List, Optional
# Importación de constructores de consulta de SQLAlchemy
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación del modelo de dominio Warehouse
from app.modules.inventory.domain.warehouse import Warehouse


class WarehouseRepository:
    """
    Repositorio de acceso a datos para la entidad Warehouse.
    Administra la persistencia de almacenes físicos y sucursales.
    """

    def __init__(self, db: AsyncSession):
        # Referencia a la sesión asíncrona de base de datos
        self.db = db

    async def get_by_id(self, warehouse_id: uuid.UUID) -> Optional[Warehouse]:
        """
        Obtiene un almacén por su identificador único UUID.
        """
        stmt = (
            select(Warehouse)
            .where(Warehouse.id == warehouse_id)
            .execution_options(populate_existing=True)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_default_warehouse(self, tenant_id: uuid.UUID) -> Optional[Warehouse]:
        """
        Obtiene el almacén predeterminado del comercio.
        """
        stmt = (
            select(Warehouse)
            .where(Warehouse.tenant_id == tenant_id, Warehouse.is_default == True)  # noqa: E712
            .order_by(Warehouse.created_at.asc())
            .execution_options(populate_existing=True)
        )
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def get_or_create_default(
        self, tenant_id: uuid.UUID, default_name: str = "Almacén Principal"
    ) -> Warehouse:
        """
        Obtiene el almacén principal o lo crea automáticamente para el comercio.
        """
        existing = await self.get_default_warehouse(tenant_id)
        if existing:
            return existing

        # Crear almacén por defecto
        default_wh = Warehouse(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            name=default_name,
            is_default=True,
        )
        self.db.add(default_wh)
        await self.db.flush()
        return default_wh

    async def list_by_tenant(self, tenant_id: uuid.UUID) -> List[Warehouse]:
        """
        Retorna la lista completa de almacenes del comercio.
        """
        stmt = (
            select(Warehouse)
            .where(Warehouse.tenant_id == tenant_id)
            .order_by(Warehouse.is_default.desc(), Warehouse.name.asc())
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def create(
        self,
        tenant_id: uuid.UUID,
        name: str,
        is_default: bool = True,
    ) -> Warehouse:
        """
        Crea e inserta un nuevo almacén en el sistema.
        """
        warehouse = Warehouse(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            name=name,
            is_default=is_default,
        )
        self.db.add(warehouse)
        await self.db.flush()
        return warehouse

    async def update(
        self,
        warehouse: Warehouse,
        name: Optional[str] = None,
        is_default: Optional[bool] = None,
    ) -> Warehouse:
        """
        Actualiza los datos de un almacén existente.
        """
        if name is not None:
            warehouse.name = name
        if is_default is not None:
            warehouse.is_default = is_default

        await self.db.flush()
        return warehouse

    async def delete(self, warehouse: Warehouse) -> None:
        """
        Elimina físicamente un almacén del sistema.
        """
        await self.db.delete(warehouse)
        await self.db.flush()
