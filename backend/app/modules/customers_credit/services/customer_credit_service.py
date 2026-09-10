# Importación de marcas temporales y zonas horarias
from datetime import datetime, timezone
# Importación de precisión decimal para montos en MXN
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de FastAPI
from fastapi import HTTPException, status
# Importación de SQLAlchemy
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de modelos de dominio
from app.modules.customers_credit.domain.credit_ledger import (
    CustomerCreditLedger,
    LedgerEntryType,
)
from app.modules.customers_credit.domain.customer import Customer
from app.modules.customers_credit.repositories.credit_ledger_repository import (
    CreditLedgerRepository,
)
from app.modules.customers_credit.repositories.customer_repository import (
    CustomerRepository,
)
from app.modules.customers_credit.schemas.customer import (
    CreditLedgerEntryResponse,
    CustomerCreateRequest,
    CustomerCreditPaymentRequest,
    CustomerCreditPaymentResponse,
    CustomerResponse,
    CustomerStatementResponse,
    CustomerUpdateRequest,
)


class CustomerCreditService:
    """
    Servicio de Dominio para Clientes, Límites de Crédito, Fiado y Cobranza (RF-06, RF-15 / Const. Art. 1.2.6, 7.2).
    """
    def __init__(self, session: AsyncSession):
        self.session = session
        self.customer_repo = CustomerRepository(session)
        self.ledger_repo = CreditLedgerRepository(session)

    async def create_customer(
        self,
        tenant_id: uuid.UUID,
        request: CustomerCreateRequest,
    ) -> CustomerResponse:
        """
        Registra un nuevo cliente con límite de crédito opcional en Pesos Mexicanos.
        """
        new_customer = Customer(
            tenant_id=tenant_id,
            full_name=request.full_name,
            phone=request.phone,
            email=request.email,
            address=request.address,
            rfc=request.rfc,
            credit_limit_mxn=request.credit_limit_mxn,
            credit_balance_mxn=Decimal("0.00"),
            credit_days=request.credit_days,
            is_active=True,
            notes=request.notes,
        )

        created = await self.customer_repo.create(new_customer)
        await self.session.commit()
        return CustomerResponse.model_validate(created)

    async def update_customer(
        self,
        tenant_id: uuid.UUID,
        customer_id: uuid.UUID,
        request: CustomerUpdateRequest,
    ) -> CustomerResponse:
        """
        Actualiza los datos o parámetros de crédito de un cliente.
        """
        customer = await self.customer_repo.get_by_id(tenant_id, customer_id)
        if not customer:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Cliente no encontrado.",
            )

        update_data = request.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            if value is not None and hasattr(customer, field):
                setattr(customer, field, value)

        customer.updated_at = datetime.now(timezone.utc)
        updated = await self.customer_repo.update(customer)
        await self.session.commit()
        return CustomerResponse.model_validate(updated)

    async def get_customer(
        self,
        tenant_id: uuid.UUID,
        customer_id: uuid.UUID,
    ) -> CustomerResponse:
        """
        Recupera el detalle de un cliente con su crédito disponible calculado.
        """
        customer = await self.customer_repo.get_by_id(tenant_id, customer_id)
        if not customer:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Cliente no encontrado.",
            )
        return CustomerResponse.model_validate(customer)

    async def list_customers(
        self,
        tenant_id: uuid.UUID,
        query: Optional[str] = None,
        has_debt_only: bool = False,
        limit: int = 50,
        offset: int = 0,
    ) -> List[CustomerResponse]:
        """
        Lista clientes con soporte de filtros y búsquedas en mostrador.
        """
        customers = await self.customer_repo.list_customers(
            tenant_id=tenant_id,
            query=query,
            has_debt_only=has_debt_only,
            limit=limit,
            offset=offset,
        )
        return [CustomerResponse.model_validate(c) for c in customers]

    async def record_credit_sale_charge(
        self,
        tenant_id: uuid.UUID,
        customer_id: uuid.UUID,
        sale_id: uuid.UUID,
        amount_mxn: Decimal,
        user_id: uuid.UUID,
    ) -> CustomerCreditLedger:
        """
        Registra un cargo inmutable por venta a crédito / fiado y valida el límite disponible.
        """
        customer = await self.customer_repo.get_by_id(tenant_id, customer_id)
        if not customer:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Cliente no encontrado para asignar la venta a crédito.",
            )

        if not customer.is_active:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El cliente se encuentra inactivo para operaciones a crédito.",
            )

        amount_to_charge = amount_mxn.quantize(Decimal("0.01"))
        new_balance = (customer.credit_balance_mxn + amount_to_charge).quantize(Decimal("0.01"))

        # Validación estricta de límite de crédito
        if new_balance > customer.credit_limit_mxn:
            available = max(Decimal("0.00"), customer.credit_limit_mxn - customer.credit_balance_mxn)
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"La venta a crédito de ${amount_to_charge:,.2f} MXN excede el límite disponible "
                    f"del cliente (${available:,.2f} MXN de un límite total de ${customer.credit_limit_mxn:,.2f} MXN)."
                ),
            )

        prev_balance = customer.credit_balance_mxn
        customer.credit_balance_mxn = new_balance

        # Crear asiento contable inmutable de cargo
        ledger_entry = CustomerCreditLedger(
            tenant_id=tenant_id,
            customer_id=customer_id,
            sale_id=sale_id,
            entry_type=LedgerEntryType.CHARGE,
            amount_mxn=amount_to_charge,
            previous_balance_mxn=prev_balance,
            resulting_balance_mxn=new_balance,
            notes="Cargo por venta a crédito en POS",
            created_by_user_id=user_id,
            created_at=datetime.now(timezone.utc),
        )

        await self.customer_repo.update(customer)
        created_entry = await self.ledger_repo.create(ledger_entry)
        await self.session.commit()
        return created_entry

    async def record_credit_payment(
        self,
        tenant_id: uuid.UUID,
        customer_id: uuid.UUID,
        user_id: uuid.UUID,
        request: CustomerCreditPaymentRequest,
    ) -> CustomerCreditPaymentResponse:
        """
        Registra un abono a la cuenta corriente del cliente, reduciendo su saldo deudor.
        """
        customer = await self.customer_repo.get_by_id(tenant_id, customer_id)
        if not customer:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Cliente no encontrado.",
            )

        amount_paid = request.amount_mxn.quantize(Decimal("0.01"))
        prev_balance = customer.credit_balance_mxn

        if prev_balance <= Decimal("0.00"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El cliente no tiene saldo deudor pendiente por liquidar.",
            )

        # Cálculo del nuevo saldo (no negativo)
        resulting_balance = max(Decimal("0.00"), prev_balance - amount_paid).quantize(Decimal("0.01"))
        customer.credit_balance_mxn = resulting_balance

        # Crear asiento de abono
        ledger_entry = CustomerCreditLedger(
            tenant_id=tenant_id,
            customer_id=customer_id,
            sale_id=request.sale_id,
            entry_type=LedgerEntryType.PAYMENT,
            amount_mxn=amount_paid,
            previous_balance_mxn=prev_balance,
            resulting_balance_mxn=resulting_balance,
            payment_method=request.payment_method,
            reference_code=request.reference_code,
            notes=request.notes or "Abono a cuenta corriente",
            created_by_user_id=user_id,
            created_at=datetime.now(timezone.utc),
        )

        await self.customer_repo.update(customer)
        created_entry = await self.ledger_repo.create(ledger_entry)
        await self.session.commit()

        available_credit = max(Decimal("0.00"), customer.credit_limit_mxn - resulting_balance)

        return CustomerCreditPaymentResponse(
            ledger_id=created_entry.id,
            customer_id=customer.id,
            customer_name=customer.full_name,
            amount_paid_mxn=amount_paid,
            previous_balance_mxn=prev_balance,
            resulting_balance_mxn=resulting_balance,
            available_credit_mxn=available_credit,
            payment_method=request.payment_method,
            reference_code=request.reference_code,
            created_at=created_entry.created_at,
        )

    async def get_customer_statement(
        self,
        tenant_id: uuid.UUID,
        customer_id: uuid.UUID,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> CustomerStatementResponse:
        """
        Genera el estado de cuenta y libro mayor de movimientos del cliente.
        """
        customer = await self.customer_repo.get_by_id(tenant_id, customer_id)
        if not customer:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Cliente no encontrado.",
            )

        entries = await self.ledger_repo.list_by_customer(
            tenant_id=tenant_id,
            customer_id=customer_id,
            start_date=start_date,
            end_date=end_date,
        )

        total_charges, total_payments = await self.ledger_repo.get_totals_by_customer(
            tenant_id=tenant_id,
            customer_id=customer_id,
            start_date=start_date,
            end_date=end_date,
        )

        available_credit = max(Decimal("0.00"), customer.credit_limit_mxn - customer.credit_balance_mxn)

        entry_responses = [CreditLedgerEntryResponse.model_validate(e) for e in entries]

        return CustomerStatementResponse(
            customer_id=customer.id,
            customer_name=customer.full_name,
            credit_limit_mxn=customer.credit_limit_mxn,
            credit_balance_mxn=customer.credit_balance_mxn,
            available_credit_mxn=available_credit,
            total_charges_mxn=total_charges.quantize(Decimal("0.01")),
            total_payments_mxn=total_payments.quantize(Decimal("0.01")),
            start_date=start_date,
            end_date=end_date,
            entries=entry_responses,
        )
