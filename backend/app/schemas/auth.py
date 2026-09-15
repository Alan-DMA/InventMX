from pydantic import BaseModel, EmailStr, Field
from uuid import UUID
from typing import Optional, List, Union

# --- Esquemas de Usuario ---
class UserRegister(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    email: EmailStr
    password: str = Field(..., min_length=6, max_length=100)

class UserResponse(BaseModel):
    id: UUID
    tenant_id: UUID
    username: str
    email: EmailStr
    role_id: Optional[UUID] = None
    is_active: bool

    class Config:
        from_attributes = True


# --- Esquemas de Tenant ---
class TenantRegister(BaseModel):
    name: str = Field(..., min_length=3, max_length=100)
    preferred_payment_method: Optional[str] = "PAGO_MOVIL"
    payment_instructions: Optional[str] = None
    plan_id: UUID
    admin_user: UserRegister

class TenantResponse(BaseModel):
    id: UUID
    code: Optional[str] = None
    name: str
    subscription_status: str
    plan_id: Optional[UUID] = None

    class Config:
        from_attributes = True


# --- Esquemas de Autenticación ---
class UserLogin(BaseModel):
    tenant_id: Optional[Union[UUID, str]] = None  # Puede ser UUID o el código comercial (ej: 150467)
    username_or_email: Optional[str] = None
    email: Optional[str] = None
    password: str

class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"

class LoginResponse(BaseModel):
    user: UserResponse
    tenant: TenantResponse
    tokens: Token

class TokenPayload(BaseModel):
    sub: str  # user_id
    type: str # access o refresh
    exp: int

class TokenData(BaseModel):
    user_id: UUID
    tenant_id: UUID
    role: str
