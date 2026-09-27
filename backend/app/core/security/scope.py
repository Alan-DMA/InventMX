"""
Alcance de datos por almacén (aislamiento por almacén, Sep 2026 — W1).

El alcance es un almacén concreto o *todos* (`None`). Quien tiene
`reports.view_advanced` (Dueño y Encargado en el seed) elige; los demás
quedan fijos en su almacén operativo aunque pidan otro. Lo decide el
servidor y no sólo la UI: si la puerta fuera del cliente, un cajero podría
pedir por API las cifras de otra sucursal.
"""
# Importación de UUID para identificadores de almacén
import uuid
# Importación de tipado estático
from typing import Optional
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación del modelo de usuario autenticado
from app.modules.auth_tenancy.domain.user import User
# Importación del repositorio de almacenes para el almacén por defecto
from app.modules.inventory.repositories.warehouse_repository import WarehouseRepository

# Permiso que habilita ver todos los almacenes juntos (D26)
VIEW_ALL_WAREHOUSES_PERMISSION = "reports.view_advanced"


def can_view_all_warehouses(user: User) -> bool:
    """El Dueño siempre; los demás si su rol trae `reports.view_advanced`."""
    if user.role and user.role.name == "OWNER":
        return True
    if not user.role or not user.role.permissions:
        return False
    return any(p.code == VIEW_ALL_WAREHOUSES_PERMISSION for p in user.role.permissions)


async def resolve_data_scope(
    db: AsyncSession,
    user: User,
    requested_warehouse_id: Optional[uuid.UUID],
) -> Optional[uuid.UUID]:
    """
    Resuelve el almacén sobre el que se calculan los datos.

    - Con permiso de ver todo: se respeta lo pedido (`None` = todos).
    - Sin él: su almacén operativo, o el principal del comercio si aún no
      tiene uno asignado. Nunca `None`, nunca otro almacén.
    """
    if can_view_all_warehouses(user):
        return requested_warehouse_id

    if user.default_warehouse_id is not None:
        return user.default_warehouse_id

    default_warehouse = await WarehouseRepository(db).get_or_create_default(user.tenant_id)
    return default_warehouse.id
