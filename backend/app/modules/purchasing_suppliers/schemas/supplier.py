# Importación de marcas de fecha y tiempo
from datetime import datetime
# Importación de precisión decimal para Pesos Mexicanos
from decimal import Decimal
# Importación de tipado estático
from typing import Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field

# Importación de enumeraciones de dominio
from app.modules.purchasing_suppliers.domain.supplier import SupplierStatus


class SupplierCreateRequest(BaseModel):
    """
    Contrato de solicitud para registro de un nuevo proveedor (RF-15 / Const. Art. 1.2.4).
    """
    # Nombre comercial o razón social
    name: str = Field(
        min_length=2,
        max_length=150,
        description="Nombre comercial o razón social del proveedor",
    )
    # RFC fiscal
    rfc: Optional[str] = Field(
        default=None,
        max_length=13,
        description="RFC fiscal del proveedor",
    )
    # Teléfono o WhatsApp
    phone: Optional[str] = Field(
        default=None,
        max_length=30,
        description="Teléfono de contacto o pedidos",
    )
    # Correo electrónico
    email: Optional[str] = Field(
        default=None,
        max_length=100,
        description="Correo electrónico institucional",
    )
    # Dirección física / fiscal
    address: Optional[str] = Field(
        default=None,
        description="Domicilio del proveedor o centro de distribución",
    )
    # Días de crédito concedidos
    credit_days: int = Field(
        default=0,
        ge=0,
        description="Días de plazo concedidos para pago de facturas",
    )
    # Límite de crédito en Pesos Mexicanos ($ MXN)
    credit_limit_mxn: Decimal = Field(
        default=Decimal("0.00"),
        ge=0,
        description="Límite máximo de crédito en Pesos Mexicanos ($ MXN)",
    )
    # Notas
    notes: Optional[str] = Field(
        default=None,
        max_length=500,
        description="Observaciones o notas sobre el proveedor",
    )


class SupplierUpdateRequest(BaseModel):
    """
    Contrato de solicitud para actualización de proveedor.
    """
    name: Optional[str] = Field(default=None, min_length=2, max_length=150)
    rfc: Optional[str] = Field(default=None, max_length=13)
    phone: Optional[str] = Field(default=None, max_length=30)
    email: Optional[str] = Field(default=None, max_length=100)
    address: Optional[str] = None
    credit_days: Optional[int] = Field(default=None, ge=0)
    credit_limit_mxn: Optional[Decimal] = Field(default=None, ge=0)
    status: Optional[SupplierStatus] = None
    notes: Optional[str] = Field(default=None, max_length=500)


class SupplierResponse(BaseModel):
    """
    Esquema de respuesta para un proveedor.
    """
    id: uuid.UUID
    tenant_id: uuid.UUID
    name: str
    rfc: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    address: Optional[str] = None
    credit_days: int
    credit_limit_mxn: Decimal
    status: SupplierStatus
    notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
