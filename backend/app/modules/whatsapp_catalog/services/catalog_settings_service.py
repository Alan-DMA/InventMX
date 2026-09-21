# Importación de precisión decimal para Pesos Mexicanos
from decimal import Decimal

# Importación de FastAPI para errores HTTP
from fastapi import HTTPException, status
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación del modelo de usuario en sesión
from app.modules.auth_tenancy.domain.user import User
from app.modules.auth_tenancy.domain.tenant import Tenant
# Importación del repositorio del catálogo
from app.modules.whatsapp_catalog.repositories.catalog_repository import CatalogRepository
from app.modules.whatsapp_catalog.domain.catalog_settings import CatalogSettings
# Importación de esquemas Pydantic
from app.modules.whatsapp_catalog.schemas.public_catalog import (
    CatalogSettingsResponse,
    CatalogSettingsUpdateRequest,
)


class CatalogSettingsService:
    """
    Servicio de configuración del Catálogo Digital de WhatsApp para el comerciante (RF-26).
    """

    def __init__(self, session: AsyncSession) -> None:
        # Sesión de base de datos
        self.session = session
        # Repositorio de acceso a datos
        self.repo = CatalogRepository(session)

    async def get_settings(self, current_user: User) -> CatalogSettingsResponse:
        """Obtiene la configuración actual del catálogo digital del tenant."""
        tenant = await self._require_tenant(current_user)
        settings = await self.repo.get_or_create_settings(current_user.tenant_id)
        # La configuración se crea en el primer GET: hay que persistirla para
        # que el PUT siguiente la encuentre (get_db sólo cierra la sesión).
        await self.session.commit()
        return self._to_response(settings, tenant)

    async def update_settings(
        self,
        request: CatalogSettingsUpdateRequest,
        current_user: User,
    ) -> CatalogSettingsResponse:
        """Actualiza parámetros operativos del catálogo digital."""
        tenant = await self._require_tenant(current_user)
        update_data = request.model_dump(exclude_unset=True)
        updated = await self.repo.update_settings(current_user.tenant_id, update_data)
        # Sin commit el cambio se revertía al cerrar la petición (mismo patrón
        # corregido en SalesService y PurchasingService, Sep 2026).
        await self.session.commit()
        return self._to_response(updated, tenant)

    async def _require_tenant(self, current_user: User) -> Tenant:
        """Obtiene el comercio de la sesión; sin él no hay slug que exponer."""
        tenant = await self.repo.get_tenant_by_id(current_user.tenant_id)
        if not tenant:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="El comercio de la sesión no existe.",
            )
        return tenant

    @staticmethod
    def _to_response(settings: CatalogSettings, tenant: Tenant) -> CatalogSettingsResponse:
        """Serializa la configuración agregando nombre y slug del comercio."""
        return CatalogSettingsResponse(
            id=settings.id,
            tenant_id=settings.tenant_id,
            store_name=tenant.name,
            store_slug=tenant.slug,
            is_catalog_enabled=settings.is_catalog_enabled,
            whatsapp_number=settings.whatsapp_number,
            welcome_message=settings.welcome_message,
            min_order_amount_mxn=settings.min_order_amount_mxn,
            delivery_fee_mxn=settings.delivery_fee_mxn,
            delivery_enabled=settings.delivery_enabled,
            pickup_enabled=settings.pickup_enabled,
            business_hours=settings.business_hours,
        )
