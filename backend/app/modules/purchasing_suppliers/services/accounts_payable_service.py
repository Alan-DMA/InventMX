# Importación de precisión decimal
from datetime import date
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional, Tuple
# Importación de identificadores UUID
import uuid
# Importación de excepciones HTTP de FastAPI
from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de entidades de dominio
from app.modules.auth_tenancy.domain.user import User
from app.modules.purchasing_suppliers.domain.account_payable import (
    AccountPayable,
    AccountPayableStatus,
    SupplierPaymentLedger,
)
from app.modules.purchasing_suppliers.repositories.account_payable_repository import (
    AccountPayableRepository,
)
from app.modules.purchasing_suppliers.schemas.account_payable import (
    AccountPayableResponse,
    AccountsPayableSummaryResponse,
    SupplierPaymentLedgerResponse,
    SupplierPaymentRequest,
    SupplierPaymentResponse,
)


class AccountsPayableService:
    """
    Servicio de lógica de negocio para Cuentas por Pagar (CxP) a Proveedores (RF-16).
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.ap_repo = AccountPayableRepository(session)

    async def list_accounts_payable(
        self,
        current_user: User,
        supplier_id: Optional[uuid.UUID] = None,
        status_filter: Optional[AccountPayableStatus] = None,
        overdue_only: bool = False,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[AccountPayableResponse], int]:
        """Lista cuentas por pagar aplicando filtros de vencimiento y proveedor."""
        items, total = await self.ap_repo.list_accounts_payable(
            tenant_id=current_user.tenant_id,
            supplier_id=supplier_id,
            status=status_filter,
            overdue_only=overdue_only,
            limit=limit,
            offset=offset,
        )
        return [self._build_response(ap) for ap in items], total

    async def get_account_payable(
        self,
        account_id: uuid.UUID,
        current_user: User,
    ) -> AccountPayableResponse:
        """Obtiene una cuenta por pagar por su ID."""
        ap = await self.ap_repo.get_by_id(account_id, current_user.tenant_id)
        if not ap:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Cuenta por pagar no encontrada.",
            )
        return self._build_response(ap)

    async def record_supplier_payment(
        self,
        account_id: uuid.UUID,
        request: SupplierPaymentRequest,
        current_user: User,
    ) -> SupplierPaymentResponse:
        """
        Registra un abono o liquidación total de una cuenta por pagar a proveedor.
        """
        # 1. Obtener la cuenta por pagar bajo aislamiento de inquilino
        ap = await self.ap_repo.get_by_id(account_id, current_user.tenant_id)
        if not ap:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Cuenta por pagar no encontrada.",
            )

        if ap.status in (AccountPayableStatus.PAID, AccountPayableStatus.CANCELLED):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"La cuenta ya está en estado {ap.status.value} y no admite nuevos abonos.",
            )

        # 2. Validar que el abono no exceda el saldo deudor pendiente
        pending_amount = (ap.total_mxn - ap.amount_paid_mxn).quantize(Decimal("0.01"))
        if request.amount_paid_mxn > pending_amount:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"El monto abonado (${request.amount_paid_mxn} MXN) excede el saldo pendiente "
                    f"(${pending_amount} MXN) de la cuenta."
                ),
            )

        # 3. Actualizar saldo acumulado y estado resultante
        previous_pending = pending_amount
        ap.amount_paid_mxn += request.amount_paid_mxn
        resulting_pending = (ap.total_mxn - ap.amount_paid_mxn).quantize(Decimal("0.01"))

        if resulting_pending <= Decimal("0.00"):
            ap.status = AccountPayableStatus.PAID
        else:
            ap.status = AccountPayableStatus.PARTIALLY_PAID

        # 4. Crear asiento contable en el libro mayor de pagos a proveedores
        payment_date = request.payment_date or date.today()
        entry = SupplierPaymentLedger(
            tenant_id=current_user.tenant_id,
            account_payable_id=ap.id,
            supplier_id=ap.supplier_id,
            amount_paid_mxn=request.amount_paid_mxn,
            payment_method=request.payment_method,
            reference_code=request.reference_code,
            payment_date=payment_date,
            notes=request.notes,
            created_by_user_id=current_user.id,
        )
        saved_entry = await self.ap_repo.create_payment_ledger(entry)

        return SupplierPaymentResponse(
            id=saved_entry.id,
            account_payable_id=ap.id,
            supplier_id=ap.supplier_id,
            supplier_name=ap.supplier.name if ap.supplier else "Proveedor",
            amount_paid_mxn=request.amount_paid_mxn,
            previous_pending_mxn=previous_pending,
            resulting_pending_mxn=resulting_pending,
            resulting_status=ap.status,
            payment_method=request.payment_method,
            reference_code=request.reference_code,
            payment_date=payment_date,
            created_at=saved_entry.created_at,
        )

    async def list_account_payments(
        self,
        account_id: uuid.UUID,
        current_user: User,
    ) -> List[SupplierPaymentLedgerResponse]:
        """Lista el historial de abonos aplicados a una cuenta por pagar."""
        ap = await self.ap_repo.get_by_id(account_id, current_user.tenant_id)
        if not ap:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Cuenta por pagar no encontrada.",
            )
        entries = await self.ap_repo.list_payments_by_account(account_id, current_user.tenant_id)
        return [SupplierPaymentLedgerResponse.model_validate(e) for e in entries]

    async def get_summary(
        self,
        current_user: User,
    ) -> AccountsPayableSummaryResponse:
        """Obtiene el resumen financiero consolidado de deudas con proveedores."""
        summary = await self.ap_repo.get_summary(current_user.tenant_id)
        return AccountsPayableSummaryResponse(**summary)

    def _build_response(self, ap: AccountPayable) -> AccountPayableResponse:
        """Mapea la entidad a su esquema de respuesta."""
        return AccountPayableResponse(
            id=ap.id,
            tenant_id=ap.tenant_id,
            supplier_id=ap.supplier_id,
            supplier_name=ap.supplier.name if ap.supplier else None,
            purchase_order_id=ap.purchase_order_id,
            folio=ap.folio,
            total_mxn=ap.total_mxn,
            amount_paid_mxn=ap.amount_paid_mxn,
            status=ap.status,
            due_date=ap.due_date,
            invoice_reference=ap.invoice_reference,
            notes=ap.notes,
            created_at=ap.created_at,
            updated_at=ap.updated_at,
        )
