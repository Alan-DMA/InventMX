import uuid
from typing import Optional
from pydantic import BaseModel, Field
from app.modules.auth_tenancy.schemas.user import UserRead
from app.modules.auth_tenancy.schemas.tenant import TenantRead


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserRead
    tenant: TenantRead


class RefreshTokenRequest(BaseModel):
    refresh_token: str = Field(..., description="JWT refresh token válido")


class RegisterTenantRequest(BaseModel):
    # Datos de la tienda
    store_name: str = Field(..., min_length=2, max_length=150, description="Nombre de la tienda/comercio")
    slug: str = Field(..., min_length=2, max_length=100, description="Slug único")
    rfc: Optional[str] = Field(default=None, max_length=13)
    # Datos del dueño (Owner)
    full_name: str = Field(..., min_length=2, max_length=150, description="Nombre completo del dueño")
    email: str = Field(..., description="Correo electrónico del dueño")
    password: str = Field(..., min_length=6, max_length=100, description="Contraseña de acceso")
