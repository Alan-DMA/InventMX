# Importación de marcas de fecha y tiempo
from datetime import date, datetime
# Importación de precisión decimal
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field, computed_field

# Importación de enumeraciones de dominio
from app.modules.purchasing_suppliers.domain.account_payable import AccountPayableStatus
from app.modules.sales_pos.domain.payment import PaymentMethod


class AccountPayableResponse(BaseModel):
    """
    Esquema de respuesta para una Cuenta por Pagar a Proveedor (RF-16).
    """
    id: uuid.UUID
    tenant_id: uuid.UUID
    supplier_id: uuid.UUID
    supplier_name: Optional[str] = None
    purchase_order_id: Optional[uuid.UUID] = None
    folio: str
    total_mxn: Decimal
    amount_paid_mxn: Decimal
    status: AccountPayableStatus
    due_date: date
    invoice_reference: Optional[str] = None
    notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    @computed_field
    @property
    def pending_amount_mxn(self) -> Decimal:
        """Saldo adeudado pendiente de liquidar ($ MXN)."""
        pending = self.total_mxn - self.amount_paid_mxn
        return max(Decimal("0.00"), pending)

    @computed_field
    @property
    def is_overdue(self) -> bool:
        """Determina si la cuenta está vencida respecto a la fecha actual."""
        if self.status in (AccountPayableStatus.PAID, AccountPayableStatus.CANCELLED):
            return False
        return date.today() > self.due_date

    model_config = ConfigDict(from_attributes=True)


class SupplierPaymentRequest(BaseModel):
    """
    Contrato de solicitud para abonar o liquidar una cuenta por pagar a proveedor (RF-16).
    """
    amount_paid_mxn: Decimal = Field(
        gt=0,
        description="Monto a pagar en Pesos Mexicanos ($ MXN) (estrictamente > 0)",
    )
    payment_method: PaymentMethod = Field(
        default=PaymentMethod.CASH_MXN,
        description="Método de pago utilizado (CASH_MXN, SPEI, CODI, CARD_TPV, OTHER)",
    )
    payment_date: Optional[date] = Field(
        default=None,
        description="Fecha del pago (por defecto hoy)",
    )
    reference_code: Optional[str] = Field(
        default=None,
        max_length=100,
        description="Folio de transferencia SPEI, cheque o voucher",
    )
    notes: Optional[str] = Field(default=None, max_length=300)


class SupplierPaymentResponse(BaseModel):
    """
    Esquema de respuesta tras registrar un pago/abono a proveedor.
    """
    id: uuid.UUID
    account_payable_id: uuid.UUID
    supplier_id: uuid.UUID
    supplier_name: str
    amount_paid_mxn: Decimal
    previous_pending_mxn: Decimal
    resulting_pending_mxn: Decimal
    resulting_status: AccountPayableStatus
    payment_method: PaymentMethod
    reference_code: Optional[str] = None
    payment_date: date
    created_at: datetime


class SupplierPaymentLedgerResponse(BaseModel):
    """
    Detalle de asiento contable de pago a proveedor.
    """
    id: uuid.UUID
    tenant_id: uuid.UUID
    account_payable_id: uuid.UUID
    supplier_id: uuid.UUID
    amount_paid_mxn: Decimal
    payment_method: PaymentMethod
    reference_code: Optional[str] = None
    payment_date: date
    notes: Optional[str] = None
    created_by_user_id: uuid.UUID
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class AccountsPayableSummaryResponse(BaseModel):
    """
    Resumen financiero consolidado de Cuentas por Pagar.
    """
    total_pending_mxn: Decimal
    total_paid_mxn: Decimal
    overdue_amount_mxn: Decimal
    overdue_count: int
    pending_count: int
