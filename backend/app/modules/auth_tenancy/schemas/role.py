import uuid
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field


class PermissionRead(BaseModel):
    id: uuid.UUID
    code: str
    description: str

    model_config = ConfigDict(from_attributes=True)


class RoleRead(BaseModel):
    id: uuid.UUID
    name: str
    description: str
    tenant_id: Optional[uuid.UUID] = None
    permissions: List[PermissionRead] = []

    model_config = ConfigDict(from_attributes=True)

    @property
    def is_custom(self) -> bool:
        """El comercio tiene su propia versión de este rol (Fase B)."""
        return self.tenant_id is not None


class RolePermissionsUpdate(BaseModel):
    """
    Permisos que quedan asignados al rol, por código (`inventory.view`…).

    Es un reemplazo completo, no un parche: la pantalla manda la lista entera
    de lo que queda encendido.
    """
    permissions: List[str] = Field(
        ...,
        description="Códigos del catálogo que quedan asignados al rol",
    )
