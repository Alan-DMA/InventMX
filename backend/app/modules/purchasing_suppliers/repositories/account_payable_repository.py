# Importación de precisión decimal
from decimal import Decimal
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
from app.modules.purchasing_suppliers.domain.account_payable import (
    AccountPayable,
    AccountPayableStatus,
    SupplierPaymentLedger,
)


class AccountPayableRepository:
    """
    Repositorio de persistencia para Cuentas por Pagar (CxP) a Proveedores.
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def generate_next_folio(self, tenant_id: uuid.UUID) -> str:
        """Genera el siguiente folio correlativo de CxP (ej: CXP-00001)."""
        stmt = select(func.count(AccountPayable.id)).where(AccountPayable.tenant_id == tenant_id)
        res = await self.session.execute(stmt)
        count = res.scalar() or 0
        return f"CXP-{(count + 1):05d}"

    async def create(self, account: AccountPayable) -> AccountPayable:
        """Persiste una nueva cuenta por pagar."""
        self.session.add(account)
        await self.session.flush()
        return account

    async def get_by_id(
        self,
        account_id: uuid.UUID,
        tenant_id: uuid.UUID,
    ) -> Optional[AccountPayable]:
        """Obtiene una cuenta por pagar por su ID con su proveedor cargado."""
        stmt = (
            select(AccountPayable)
            .where(
                AccountPayable.id == account_id,
                AccountPayable.tenant_id == tenant_id,
            )
            .options(selectinload(AccountPayable.supplier))
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_purchase_order_id(
        self,
        purchase_order_id: uuid.UUID,
        tenant_id: uuid.UUID,
    ) -> Optional[AccountPayable]:
        """Obtiene la cuenta por pagar asociada a una orden de compra."""
        stmt = select(AccountPayable).where(
            AccountPayable.purchase_order_id == purchase_order_id,
            AccountPayable.tenant_id == tenant_id,
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_accounts_payable(
        self,
        tenant_id: uuid.UUID,
        supplier_id: Optional[uuid.UUID] = None,
        status: Optional[AccountPayableStatus] = None,
        overdue_only: bool = False,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[AccountPayable], int]:
        """Lista cuentas por pagar aplicando filtros de proveedor, estado o vencimiento."""
        base_query = select(AccountPayable).where(AccountPayable.tenant_id == tenant_id)
        count_query = select(func.count(AccountPayable.id)).where(AccountPayable.tenant_id == tenant_id)

        if supplier_id:
            base_query = base_query.where(AccountPayable.supplier_id == supplier_id)
            count_query = count_query.where(AccountPayable.supplier_id == supplier_id)

        if status:
            base_query = base_query.where(AccountPayable.status == status)
            count_query = count_query.where(AccountPayable.status == status)

        if overdue_only:
            today = date.today()
            base_query = base_query.where(
                AccountPayable.due_date < today,
                AccountPayable.status.in_([AccountPayableStatus.PENDING, AccountPayableStatus.PARTIALLY_PAID, AccountPayableStatus.OVERDUE]),
            )
            count_query = count_query.where(
                AccountPayable.due_date < today,
                AccountPayable.status.in_([AccountPayableStatus.PENDING, AccountPayableStatus.PARTIALLY_PAID, AccountPayableStatus.OVERDUE]),
            )

        total_res = await self.session.execute(count_query)
        total = total_res.scalar() or 0

        stmt = (
            base_query.options(selectinload(AccountPayable.supplier))
            .order_by(AccountPayable.due_date.asc())
            .limit(limit)
            .offset(offset)
        )
        res = await self.session.execute(stmt)
        return list(res.scalars().all()), total

    async def create_payment_ledger(self, entry: SupplierPaymentLedger) -> SupplierPaymentLedger:
        """Registra un asiento contable de abono a proveedor."""
        self.session.add(entry)
        await self.session.flush()
        return entry

    async def list_payments_by_account(
        self,
        account_payable_id: uuid.UUID,
        tenant_id: uuid.UUID,
    ) -> List[SupplierPaymentLedger]:
        """Lista los abonos aplicados a una cuenta por pagar."""
        stmt = (
            select(SupplierPaymentLedger)
            .where(
                SupplierPaymentLedger.account_payable_id == account_payable_id,
                SupplierPaymentLedger.tenant_id == tenant_id,
            )
            .order_by(SupplierPaymentLedger.created_at.desc())
        )
        res = await self.session.execute(stmt)
        return list(res.scalars().all())

    async def get_summary(self, tenant_id: uuid.UUID) -> dict:
        """Calcula el resumen agregado de saldos y cuentas vencidas en $ MXN."""
        today = date.today()
        stmt = select(
            func.coalesce(func.sum(AccountPayable.total_mxn), Decimal("0.00")),
            func.coalesce(func.sum(AccountPayable.amount_paid_mxn), Decimal("0.00")),
        ).where(
            AccountPayable.tenant_id == tenant_id,
            AccountPayable.status.in_([AccountPayableStatus.PENDING, AccountPayableStatus.PARTIALLY_PAID, AccountPayableStatus.OVERDUE]),
        )
        res = await self.session.execute(stmt)
        total_sum, paid_sum = res.one()
        total_pending = max(Decimal("0.00"), total_sum - paid_sum)

        # Cuentas vencidas
        overdue_stmt = select(
            func.coalesce(func.sum(AccountPayable.total_mxn - AccountPayable.amount_paid_mxn), Decimal("0.00")),
            func.count(AccountPayable.id),
        ).where(
            AccountPayable.tenant_id == tenant_id,
            AccountPayable.due_date < today,
            AccountPayable.status.in_([AccountPayableStatus.PENDING, AccountPayableStatus.PARTIALLY_PAID, AccountPayableStatus.OVERDUE]),
        )
        overdue_res = await self.session.execute(overdue_stmt)
        overdue_amount, overdue_count = overdue_res.one()

        # Conteo total de pendientes
        pending_count_stmt = select(func.count(AccountPayable.id)).where(
            AccountPayable.tenant_id == tenant_id,
            AccountPayable.status.in_([AccountPayableStatus.PENDING, AccountPayableStatus.PARTIALLY_PAID, AccountPayableStatus.OVERDUE]),
        )
        pending_count_res = await self.session.execute(pending_count_stmt)
        pending_count = pending_count_res.scalar() or 0

        return {
            "total_pending_mxn": total_pending,
            "total_paid_mxn": paid_sum,
            "overdue_amount_mxn": overdue_amount,
            "overdue_count": overdue_count,
            "pending_count": pending_count,
        }
