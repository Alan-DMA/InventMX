# Importación de UUID para tipado de identificadores
import uuid
# Importación de datetime para marcas de tiempo
from datetime import datetime
# Importación de tipos estáticos
from typing import Optional
# Importación de constructs de Pydantic v2
from pydantic import BaseModel, ConfigDict, EmailStr, Field

# Importación de esquema de lectura de roles
from app.modules.auth_tenancy.schemas.role import RoleRead


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


class UserRead(UserBase):
    """Esquema para retorno de datos de usuario con relaciones."""
    id: uuid.UUID
    tenant_id: uuid.UUID
    role_id: uuid.UUID
    role: Optional[RoleRead] = None
    is_active: bool
    created_at: datetime
    updated_at: datetime

    # Configuración para permitir instanciación directa desde modelos SQLAlchemy
    model_config = ConfigDict(from_attributes=True)
