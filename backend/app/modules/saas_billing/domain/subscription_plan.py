# Importación de precisión decimal para importes monetarios en MXN
from decimal import Decimal
# Importación de enumeraciones nativas
from enum import Enum
# Importación de tipado estático
from typing import Dict, List, Optional
# Importación de modelos Pydantic
from pydantic import BaseModel, Field

# Importación de la enumeración canónica de planes de suscripción
from app.modules.auth_tenancy.domain.tenant import TenantPlan


class PlanFeature(BaseModel):
    """
    Modelo de valor para describir una característica individual de un plan de suscripción.
    """
    code: str = Field(..., description="Código único de la funcionalidad")
    name: str = Field(..., description="Nombre descriptivo de la funcionalidad")
    included: bool = Field(..., description="Indica si el plan incluye esta funcionalidad")
    limit: Optional[int] = Field(None, description="Límite numérico aplicable (ej. cantidad de usuarios)")


class PlanTier(BaseModel):
    """
    Definición canónica de un nivel o plan de suscripción en Nexus SaaS.
    Regla de negocio: Documento Maestro Día 14 y Constitución Artículo VI.
    - EMPRENDEDOR: $199 MXN / mes (Abarrotes y micro-comercios con 1 usuario y 1 sucursal)
    - COMERCIO: $399 MXN / mes (Comercios en crecimiento con turnos de caja, comisiones y hasta 5 usuarios)
    - CORPORATIVO: $699 MXN / mes (Empresas multi-sucursal con analítica avanzada y usuarios ilimitados)
    """
    id: TenantPlan = Field(..., description="Identificador único del plan")
    name: str = Field(..., description="Nombre público del plan")
    description: str = Field(..., description="Descripción del perfil de negocio objetivo")
    monthly_price_mxn: Decimal = Field(..., description="Precio mensual en Pesos Mexicanos (MXN)")
    annual_price_mxn: Decimal = Field(..., description="Precio anual con descuento en Pesos Mexicanos (MXN)")
    max_users: int = Field(..., description="Límite máximo de usuarios cajeros/administradores (-1 para ilimitado)")
    max_warehouses: int = Field(..., description="Límite máximo de almacenes o sucursales (-1 para ilimitado)")
    max_products: int = Field(..., description="Límite máximo de productos registrados en catálogo (-1 para ilimitado)")
    max_monthly_sales_mxn: Optional[Decimal] = Field(None, description="Límite mensual de volumen de ventas en MXN si aplica")
    cash_registers_allowed: bool = Field(..., description="Permite gestión de turnos de caja y arqueos físicos Banxico")
    commissions_allowed: bool = Field(..., description="Permite cálculo y liquidación de comisiones a vendedores")
    advanced_reports_allowed: bool = Field(..., description="Permite acceso a reportes financieros avanzados y COGS")
    b2b_community_allowed: bool = Field(..., description="Permite publicar y comprar en el marketplace comunitario B2B")
    whatsapp_catalog_allowed: bool = Field(..., description="Permite tienda pública en línea con pedidos vía WhatsApp")


# Catálogo canónico de planes SaaS Nexus MX con sus respectivas reglas comerciales
AVAILABLE_PLANS: Dict[TenantPlan, PlanTier] = {
    # Plan Emprendedor: entrada básica para micronegocios individuales
    TenantPlan.EMPRENDEDOR: PlanTier(
        id=TenantPlan.EMPRENDEDOR,
        name="Plan Emprendedor",
        description="Ideal para microcomercios, tiendas de abarrotes y emprendedores que inician su digitalización.",
        monthly_price_mxn=Decimal("199.00"),
        annual_price_mxn=Decimal("1990.00"),
        max_users=1,
        max_warehouses=1,
        max_products=1000,
        max_monthly_sales_mxn=Decimal("50000.00"),
        cash_registers_allowed=False,
        commissions_allowed=False,
        advanced_reports_allowed=False,
        b2b_community_allowed=False,
        whatsapp_catalog_allowed=True,
    ),
    # Plan Comercio: solución completa para puntos de venta con personal
    TenantPlan.COMERCIO: PlanTier(
        id=TenantPlan.COMERCIO,
        name="Plan Comercio",
        description="Para comercios con empleados, control riguroso de caja, turnos y comisiones dinámicas.",
        monthly_price_mxn=Decimal("399.00"),
        annual_price_mxn=Decimal("3990.00"),
        max_users=5,
        max_warehouses=3,
        max_products=5000,
        max_monthly_sales_mxn=Decimal("200000.00"),
        cash_registers_allowed=True,
        commissions_allowed=True,
        advanced_reports_allowed=True,
        b2b_community_allowed=True,
        whatsapp_catalog_allowed=True,
    ),
    # Plan Corporativo: escalabilidad total para cadenas locales y distribuidores
    TenantPlan.CORPORATIVO: PlanTier(
        id=TenantPlan.CORPORATIVO,
        name="Plan Corporativo",
        description="Capacidad ilimitada, sucursales múltiples, auditoría completa y analítica financiera ejecutiva.",
        monthly_price_mxn=Decimal("699.00"),
        annual_price_mxn=Decimal("6990.00"),
        max_users=-1,
        max_warehouses=-1,
        max_products=-1,
        max_monthly_sales_mxn=None,
        cash_registers_allowed=True,
        commissions_allowed=True,
        advanced_reports_allowed=True,
        b2b_community_allowed=True,
        whatsapp_catalog_allowed=True,
    ),
}
