# Importación de marcas de tiempo
from datetime import datetime
# Importación de precisión decimal
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional, Tuple
# Importación de UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de entidades y enums
from app.modules.customers_credit.domain.credit_ledger import (
    CustomerCreditLedger,
    LedgerEntryType,
)


class CreditLedgerRepository:
    """
    Repositorio de persistencia asíncrona para el Libro Mayor de Crédito (inventmx.customer_credit_ledger) (RF-15).
    """
    def __init__(self, session: AsyncSession):
        self.session = session

    async def create(self, entry: CustomerCreditLedger) -> CustomerCreditLedger:
        """
        Inserta un nuevo asiento inmutable en el libro mayor.
        """
        self.session.add(entry)
        await self.session.flush()
        await self.session.refresh(entry)
        return entry

    async def list_by_customer(
        self,
        tenant_id: uuid.UUID,
        customer_id: uuid.UUID,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        limit: int = 100,
        offset: int = 0,
    ) -> List[CustomerCreditLedger]:
        """
        Obtiene el historial cronológico de movimientos de crédito de un cliente.
        """
        stmt = (
            select(CustomerCreditLedger)
            .where(
                CustomerCreditLedger.tenant_id == tenant_id,
                CustomerCreditLedger.customer_id == customer_id,
            )
        )

        if start_date:
            stmt = stmt.where(CustomerCreditLedger.created_at >= start_date)

        if end_date:
            stmt = stmt.where(CustomerCreditLedger.created_at <= end_date)

        stmt = stmt.order_by(desc(CustomerCreditLedger.created_at)).offset(offset).limit(limit)
        result = await self.session.execute(stmt)
        return list(result.scalars().all())

    async def get_totals_by_customer(
        self,
        tenant_id: uuid.UUID,
        customer_id: uuid.UUID,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> Tuple[Decimal, Decimal]:
        """
        Calcula la suma acumulada de cargos y abonos para el estado de cuenta.
        Retorna (total_charges_mxn, total_payments_mxn).
        """
        stmt_charges = select(func.coalesce(func.sum(CustomerCreditLedger.amount_mxn), Decimal("0.00"))).where(
            CustomerCreditLedger.tenant_id == tenant_id,
            CustomerCreditLedger.customer_id == customer_id,
            CustomerCreditLedger.entry_type == LedgerEntryType.CHARGE,
        )
        stmt_payments = select(func.coalesce(func.sum(CustomerCreditLedger.amount_mxn), Decimal("0.00"))).where(
            CustomerCreditLedger.tenant_id == tenant_id,
            CustomerCreditLedger.customer_id == customer_id,
            CustomerCreditLedger.entry_type == LedgerEntryType.PAYMENT,
        )

        if start_date:
            stmt_charges = stmt_charges.where(CustomerCreditLedger.created_at >= start_date)
            stmt_payments = stmt_payments.where(CustomerCreditLedger.created_at >= start_date)

        if end_date:
            stmt_charges = stmt_charges.where(CustomerCreditLedger.created_at <= end_date)
            stmt_payments = stmt_payments.where(CustomerCreditLedger.created_at <= end_date)

        res_charges = await self.session.execute(stmt_charges)
        res_payments = await self.session.execute(stmt_payments)

        total_charges = Decimal(str(res_charges.scalar() or Decimal("0.00")))
        total_payments = Decimal(str(res_payments.scalar() or Decimal("0.00")))

        return total_charges, total_payments
