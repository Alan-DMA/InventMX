# Importación de tipos decimales
from decimal import Decimal
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.tenant import Tenant
from app.modules.auth_tenancy.domain.user import User
# Importación de repositorios
from app.modules.auth_tenancy.repositories.tenant_repository import TenantRepository


class TenantService:
    """
    Servicio de lógica de negocio para la configuración a nivel comercio
    (Tenant) — hoy sólo cubre precios (margen máximo sugerido).
    """

    def __init__(self, db: AsyncSession):
        self.db = db
        self.tenant_repo = TenantRepository(db)

    async def update_pricing_settings(
        self, max_margin_percent: Decimal, current_user: User
    ) -> Tenant:
        """
        Actualiza el margen máximo sugerido del comercio en sesión.
        """
        tenant = current_user.tenant
        updated = await self.tenant_repo.update_max_margin_percent(
            tenant, max_margin_percent
        )
        await self.db.commit()
        return updated
