# Importación de marcas de fecha y tiempo
from datetime import datetime
# Importación de precisión decimal para montos monetarios en MXN
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field, computed_field

# Importación de enumeraciones de dominio
from app.modules.customers_credit.domain.credit_ledger import LedgerEntryType
from app.modules.sales_pos.domain.payment import PaymentMethod


class CustomerCreateRequest(BaseModel):
    """
    Contrato de solicitud para registro de un nuevo cliente (RF-06 / Const. Art. 1.2.6).
    """
    # Nombre completo o razón social
    full_name: str = Field(
        min_length=2,
        max_length=150,
        description="Nombre completo o razón social del cliente",
    )
    # Teléfono o WhatsApp (opcional)
    phone: Optional[str] = Field(
        default=None,
        max_length=30,
        description="Número de teléfono o WhatsApp",
    )
    # Correo electrónico (opcional)
    email: Optional[str] = Field(
        default=None,
        max_length=100,
        description="Correo electrónico del cliente",
    )
    # Domicilio físico (opcional)
    address: Optional[str] = Field(
        default=None,
        description="Dirección o domicilio del cliente",
    )
    # RFC (opcional)
    rfc: Optional[str] = Field(
        default=None,
        max_length=13,
        description="RFC fiscal del cliente",
    )
    # Límite de crédito otorgado en MXN ($)
    credit_limit_mxn: Decimal = Field(
        default=Decimal("0.00"),
        ge=0,
        description="Límite máximo de crédito en Pesos Mexicanos ($ MXN)",
    )
    # Plazo de crédito en días
    credit_days: int = Field(
        default=0,
        ge=0,
        description="Plazo máximo en días concedido para liquidar créditos",
    )
    # Notas adicionales
    notes: Optional[str] = Field(
        default=None,
        max_length=500,
        description="Notas u observaciones sobre el cliente",
    )


class CustomerUpdateRequest(BaseModel):
    """
    Contrato de solicitud para actualización de datos o línea de crédito de un cliente.
    """
    full_name: Optional[str] = Field(default=None, min_length=2, max_length=150)
    phone: Optional[str] = Field(default=None, max_length=30)
    email: Optional[str] = Field(default=None, max_length=100)
    address: Optional[str] = None
    rfc: Optional[str] = Field(default=None, max_length=13)
    credit_limit_mxn: Optional[Decimal] = Field(default=None, ge=0)
    credit_days: Optional[int] = Field(default=None, ge=0)
    is_active: Optional[bool] = None
    notes: Optional[str] = Field(default=None, max_length=500)


class CustomerResponse(BaseModel):
    """
    Esquema de respuesta para los datos de un cliente con su situación crediticia calculada.
    """
    # Identificador único
    id: uuid.UUID
    # Identificador del inquilino
    tenant_id: uuid.UUID
    # Nombre
    full_name: str
    # Teléfono
    phone: Optional[str] = None
    # Correo
    email: Optional[str] = None
    # Dirección
    address: Optional[str] = None
    # RFC
    rfc: Optional[str] = None
    # Límite de crédito
    credit_limit_mxn: Decimal
    # Saldo deudor actual
    credit_balance_mxn: Decimal
    # Plazo en días
    credit_days: int
    # Estado activo
    is_active: bool
    # Notas
    notes: Optional[str] = None
    # Fecha de creación
    created_at: datetime
    # Fecha de actualización
    updated_at: datetime

    @computed_field
    @property
    def available_credit_mxn(self) -> Decimal:
        """Crédito disponible para nuevas compras (Límite - Saldo deudor)."""
        available = self.credit_limit_mxn - self.credit_balance_mxn
        return max(Decimal("0.00"), available)

    model_config = ConfigDict(from_attributes=True)


class CustomerCreditPaymentRequest(BaseModel):
    """
    Contrato de solicitud para registro de un abono o pago a cuenta de crédito (RF-15).
    """
    # Monto en Pesos Mexicanos a abonar
    amount_mxn: Decimal = Field(
        gt=0,
        description="Monto a abonar en Pesos Mexicanos ($ MXN) (estrictamente > 0)",
    )
    # Método de pago utilizado
    payment_method: PaymentMethod = Field(
        default=PaymentMethod.CASH_MXN,
        description="Método de pago utilizado para liquidar o abonar a la cuenta",
    )
    # Identificador opcional de la venta que se liquida
    sale_id: Optional[uuid.UUID] = Field(
        default=None,
        description="Identificador de la nota de venta específica que se abona (opcional)",
    )
    # Folio bancario o referencia
    reference_code: Optional[str] = Field(
        default=None,
        max_length=100,
        description="Folio de transferencia SPEI o voucher de tarjeta",
    )
    # Notas explicativas
    notes: Optional[str] = Field(
        default=None,
        max_length=500,
        description="Notas u observaciones del abono",
    )


class CustomerCreditPaymentResponse(BaseModel):
    """
    Esquema de respuesta tras asentar exitosamente un abono a cuenta corriente.
    """
    # Identificador del asiento contable
    ledger_id: uuid.UUID
    # Identificador del cliente
    customer_id: uuid.UUID
    # Nombre del cliente
    customer_name: str
    # Monto abonado
    amount_paid_mxn: Decimal
    # Saldo anterior
    previous_balance_mxn: Decimal
    # Saldo deudor resultante
    resulting_balance_mxn: Decimal
    # Crédito disponible resultante
    available_credit_mxn: Decimal
    # Método de pago
    payment_method: PaymentMethod
    # Código de referencia
    reference_code: Optional[str] = None
    # Fecha de registro
    created_at: datetime


class CreditLedgerEntryResponse(BaseModel):
    """
    Esquema de respuesta para un asiento contable individual en el libro mayor de crédito.
    """
    id: uuid.UUID
    tenant_id: uuid.UUID
    customer_id: uuid.UUID
    sale_id: Optional[uuid.UUID] = None
    entry_type: LedgerEntryType
    amount_mxn: Decimal
    previous_balance_mxn: Decimal
    resulting_balance_mxn: Decimal
    payment_method: Optional[PaymentMethod] = None
    reference_code: Optional[str] = None
    notes: Optional[str] = None
    created_by_user_id: uuid.UUID
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class CustomerStatementResponse(BaseModel):
    """
    Esquema de respuesta para el estado de cuenta consolidado del cliente.
    """
    customer_id: uuid.UUID
    customer_name: str
    credit_limit_mxn: Decimal
    credit_balance_mxn: Decimal
    available_credit_mxn: Decimal
    total_charges_mxn: Decimal
    total_payments_mxn: Decimal
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    entries: List[CreditLedgerEntryResponse] = Field(default_factory=list)
