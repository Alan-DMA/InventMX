# Importación de UUID para tipado de identificadores
import uuid
# Importación de datetime para marcas de tiempo
from datetime import datetime
# Importación de Decimal para tasas de comisión
from decimal import Decimal
# Importación de tipos estáticos
from typing import Optional
# Importación de constructs de Pydantic v2
from pydantic import BaseModel, ConfigDict, EmailStr, Field

# Importación de esquema de lectura de roles
from app.modules.auth_tenancy.schemas.role import RoleRead
# Esquema de comisión (RF-10) — mismo enum que los asientos de sale_commissions
from app.modules.sales_pos.domain.commission import CommissionType


class UserBase(BaseModel):
    """Esquema base con atributos comunes de usuario."""
    email: EmailStr = Field(..., description="Correo electrónico único del usuario")
    full_name: str = Field(..., min_length=2, max_length=150, description="Nombre completo")


class UserCreate(UserBase):
    """Esquema para creación de nuevo empleado."""
    password: str = Field(..., min_length=6, max_length=100, description="Contraseña de acceso")
    role_id: uuid.UUID = Field(..., description="Identificador UUID del rol a asignar")


class UserLogin(BaseModel):
    """Esquema de credenciales para inicio de sesión."""
    email: EmailStr = Field(..., description="Correo electrónico registrado")
    password: str = Field(..., description="Contraseña de acceso")


class UserUpdate(BaseModel):
    """Esquema para modificación parcial de datos de empleado."""
    full_name: Optional[str] = Field(default=None, min_length=2, max_length=150)
    password: Optional[str] = Field(default=None, min_length=6, max_length=100)
    role_id: Optional[uuid.UUID] = Field(default=None, description="Nuevo rol asignado al empleado")
    is_active: Optional[bool] = Field(default=None, description="Estado activo/inactivo del empleado")
    commission_type: Optional[CommissionType] = Field(
        default=None,
        description="Esquema de comisión: PERCENTAGE_SALE, PERCENTAGE_PROFIT o FIXED_PER_SALE (RF-10)",
    )
    commission_rate: Optional[Decimal] = Field(
        default=None,
        ge=0,
        max_digits=5,
        decimal_places=2,
        description="Porcentaje (0-100) o monto fijo en $ MXN por venta; 0 desactiva la comisión",
    )
    default_warehouse_id: Optional[uuid.UUID] = Field(
        default=None,
        description="Almacén operativo asignado al empleado por quien administra la tienda (settings.manage_users)",
    )


class UserRead(UserBase):
    """Esquema para retorno de datos de usuario con relaciones."""
    id: uuid.UUID
    tenant_id: uuid.UUID
    role_id: uuid.UUID
    role: Optional[RoleRead] = None
    is_active: bool
    default_warehouse_id: Optional[uuid.UUID] = Field(
        default=None,
        description="Almacén operativo actual del usuario, configurable desde su perfil.",
    )
    commission_type: CommissionType = Field(
        default=CommissionType.PERCENTAGE_SALE,
        description="Esquema de comisión del empleado (RF-10)",
    )
    commission_rate: Decimal = Field(
        default=Decimal("0.00"),
        description="Porcentaje o monto fijo de comisión; 0 = no comisiona",
    )
    created_at: datetime
    updated_at: datetime

    # Configuración para permitir instanciación directa desde modelos SQLAlchemy
    model_config = ConfigDict(from_attributes=True)


class UpdateOperatingWarehouseRequest(BaseModel):
    """Esquema de entrada para que el usuario en sesión cambie su almacén operativo."""
    warehouse_id: uuid.UUID = Field(
        ..., description="ID del almacén al que el usuario quiere operar",
    )
