# Importación de precisión decimal para Pesos Mexicanos
from decimal import Decimal
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación del usuario autenticado
from app.modules.auth_tenancy.domain.user import User
# Importación del repositorio de catálogo
from app.modules.whatsapp_catalog.repositories.catalog_repository import CatalogRepository
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
        self.session = session
        self.repo = CatalogRepository(session)

    async def get_settings(self, current_user: User) -> CatalogSettingsResponse:
        """Obtiene la configuración actual del catálogo digital del tenant."""
        settings = await self.repo.get_or_create_settings(current_user.tenant_id)
        return CatalogSettingsResponse.model_validate(settings)

    async def update_settings(
        self,
        request: CatalogSettingsUpdateRequest,
        current_user: User,
    ) -> CatalogSettingsResponse:
        """Actualiza parámetros operativos del catálogo digital."""
        update_data = request.model_dump(exclude_unset=True)
        updated = await self.repo.update_settings(current_user.tenant_id, update_data)
        return CatalogSettingsResponse.model_validate(updated)
