# Importación de marcas temporales
from datetime import datetime
# Importación de tipado estático
from typing import List, Optional
# Importación de UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import desc, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

# Importación del modelo de dominio de clientes
from app.modules.customers_credit.domain.customer import Customer


class CustomerRepository:
    """
    Repositorio de persistencia asíncrona para Clientes (inventmx.customers) (RF-06).
    Garantiza aislamiento multi-inquilino y soporte de búsquedas avanzadas en mostrador.
    """
    def __init__(self, session: AsyncSession):
        # Sesión asíncrona de base de datos
        self.session = session

    async def create(self, customer: Customer) -> Customer:
        """
        Inserta un nuevo cliente en la base de datos.
        """
        self.session.add(customer)
        await self.session.flush()
        await self.session.refresh(customer)
        return customer

    async def get_by_id(
        self,
        tenant_id: uuid.UUID,
        customer_id: uuid.UUID,
    ) -> Optional[Customer]:
        """
        Recupera un cliente por su ID universal bajo aislamiento RLS.
        """
        stmt = (
            select(Customer)
            .where(
                Customer.id == customer_id,
                Customer.tenant_id == tenant_id,
            )
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_customers(
        self,
        tenant_id: uuid.UUID,
        query: Optional[str] = None,
        has_debt_only: bool = False,
        limit: int = 50,
        offset: int = 0,
    ) -> List[Customer]:
        """
        Lista clientes del inquilino con filtros de búsqueda por nombre/teléfono/RFC y saldo deudor.
        """
        stmt = select(Customer).where(Customer.tenant_id == tenant_id)

        # Filtro de búsqueda por texto
        if query and query.strip():
            pattern = f"%{query.strip()}%"
            stmt = stmt.where(
                or_(
                    Customer.full_name.ilike(pattern),
                    Customer.phone.ilike(pattern),
                    Customer.rfc.ilike(pattern),
                    Customer.email.ilike(pattern),
                )
            )

        # Filtro de solo clientes con saldo deudor
        if has_debt_only:
            stmt = stmt.where(Customer.credit_balance_mxn > 0)

        # Orden alfabético y paginación
        stmt = stmt.order_by(Customer.full_name.asc()).offset(offset).limit(limit)
        result = await self.session.execute(stmt)
        return list(result.scalars().all())

    async def update(self, customer: Customer) -> Customer:
        """
        Actualiza los datos o saldo del cliente.
        """
        self.session.add(customer)
        await self.session.flush()
        await self.session.refresh(customer)
        return customer
