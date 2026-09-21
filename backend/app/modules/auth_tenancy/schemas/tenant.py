import uuid
from datetime import datetime
from decimal import Decimal
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field
from app.modules.auth_tenancy.domain.tenant import TenantPlan, TenantStatus


class TenantBase(BaseModel):
    name: str = Field(..., min_length=2, max_length=150, description="Nombre comercial de la tienda")
    slug: str = Field(..., min_length=2, max_length=100, description="Identificador único para URL/catálogo")
    plan_id: TenantPlan = Field(default=TenantPlan.EMPRENDEDOR)
    rfc: Optional[str] = Field(default=None, max_length=13, description="RFC fiscal de México (opcional)")
    legal_name: Optional[str] = Field(default=None, max_length=200, description="Razón social (opcional)")
    enable_usd_secondary: bool = Field(default=False, description="Habilitar cobro en USD secundario para frontera norte")


class TenantCreate(TenantBase):
    pass


class TenantUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=2, max_length=150)
    rfc: Optional[str] = Field(default=None, max_length=13)
    legal_name: Optional[str] = Field(default=None, max_length=200)
    enable_usd_secondary: Optional[bool] = None


class TenantRead(TenantBase):
    id: uuid.UUID
    status: TenantStatus
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class PricingSettingsResponse(BaseModel):
    """
    Configuración de precios del comercio — hoy sólo el margen máximo
    sugerido, usado como piso del "precio máximo sugerido" por producto
    mientras no haya suficiente historial de ventas (decisión de Eduardo,
    Sep 2026).
    """
    max_margin_percent: Decimal = Field(
        description="Margen máximo sugerido (%) sobre costo",
    )

    model_config = ConfigDict(from_attributes=True)


class PricingSettingsUpdateRequest(BaseModel):
    """
    Esquema de entrada para actualizar el margen máximo sugerido del comercio.
    """
    max_margin_percent: Decimal = Field(
        ge=0,
        le=1000,
        description="Margen máximo sugerido (%) sobre costo",
    )
