# Importación de tipado estático
from typing import List, Optional, Tuple
# Importación de identificadores UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de modelos de dominio
from app.modules.purchasing_suppliers.domain.supplier import Supplier, SupplierStatus


class SupplierRepository:
    """
    Repositorio de persistencia asíncrona para la entidad Proveedor (Supplier).
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(self, supplier: Supplier) -> Supplier:
        """Persiste un nuevo proveedor en la base de datos."""
        self.session.add(supplier)
        await self.session.flush()
        return supplier

    async def get_by_id(self, supplier_id: uuid.UUID, tenant_id: uuid.UUID) -> Optional[Supplier]:
        """Obtiene un proveedor por su ID bajo aislamiento de inquilino."""
        stmt = select(Supplier).where(
            Supplier.id == supplier_id,
            Supplier.tenant_id == tenant_id,
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_suppliers(
        self,
        tenant_id: uuid.UUID,
        search: Optional[str] = None,
        status: Optional[SupplierStatus] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[Supplier], int]:
        """Lista proveedores aplicando filtros de búsqueda y paginación."""
        base_query = select(Supplier).where(Supplier.tenant_id == tenant_id)
        count_query = select(func.count(Supplier.id)).where(Supplier.tenant_id == tenant_id)

        if search:
            pattern = f"%{search.strip()}%"
            filter_clause = or_(
                Supplier.name.ilike(pattern),
                Supplier.rfc.ilike(pattern),
                Supplier.phone.ilike(pattern),
            )
            base_query = base_query.where(filter_clause)
            count_query = count_query.where(filter_clause)

        if status:
            base_query = base_query.where(Supplier.status == status)
            count_query = count_query.where(Supplier.status == status)

        # Conteo total
        total_res = await self.session.execute(count_query)
        total = total_res.scalar() or 0

        # Paginación y orden alfabético
        stmt = base_query.order_by(Supplier.name.asc()).limit(limit).offset(offset)
        res = await self.session.execute(stmt)
        return list(res.scalars().all()), total

    async def update(self, supplier: Supplier) -> Supplier:
        """Actualiza un proveedor y actualiza la sesión."""
        await self.session.flush()
        return supplier
