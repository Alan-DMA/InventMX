# Importación de marcas de tiempo
from datetime import datetime, timezone
# Importación de tipado estático
from typing import Optional
# Importación de identificadores UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación del modelo de dominio de configuración de tickets
from app.modules.sales_pos.domain.ticket_settings import TicketSettings
from app.modules.sales_pos.schemas.ticket import TicketSettingsUpdateRequest


class TicketRepository:
    """
    Repositorio de persistencia asíncrona para la configuración de tickets de venta (RF-08 / Const. Art. 1.2.8).
    """
    def __init__(self, session: AsyncSession):
        # Sesión asíncrona de base de datos
        self.session = session

    async def get_by_tenant(self, tenant_id: uuid.UUID) -> Optional[TicketSettings]:
        """
        Recupera la configuración de tickets del comercio por su tenant_id.
        """
        query = select(TicketSettings).where(TicketSettings.tenant_id == tenant_id)
        result = await self.session.execute(query)
        return result.scalar_one_or_none()

    async def get_or_create_default(
        self,
        tenant_id: uuid.UUID,
        default_business_name: Optional[str] = None,
    ) -> TicketSettings:
        """
        Recupera la configuración existente o crea una predeterminada si no existe.
        """
        existing = await self.get_by_tenant(tenant_id)
        if existing:
            return existing

        # Crear configuración predeterminada higiénica (58mm, pie estándar)
        new_settings = TicketSettings(
            tenant_id=tenant_id,
            business_name=default_business_name or "Mi Comercio POS",
            legal_name=None,
            rfc=None,
            address=None,
            phone=None,
            email=None,
            footer_message="¡Gracias por su compra!",
            paper_width_mm=58,
            show_savings=True,
            show_cashier_name=True,
            show_taxes=False,
        )
        self.session.add(new_settings)
        await self.session.flush()
        return new_settings

    async def update_settings(
        self,
        settings: TicketSettings,
        update_req: TicketSettingsUpdateRequest,
    ) -> TicketSettings:
        """
        Actualiza los parámetros configurables del ticket.
        """
        update_data = update_req.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            if hasattr(settings, field):
                setattr(settings, field, value)

        settings.updated_at = datetime.now(timezone.utc)
        await self.session.flush()
        return settings
