import uuid
from typing import List, Optional
from pydantic import BaseModel, ConfigDict


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
