# Exportación centralizada de todos los repositorios del módulo auth_tenancy
from app.modules.auth_tenancy.repositories.role_repository import RoleRepository
from app.modules.auth_tenancy.repositories.tenant_repository import TenantRepository
from app.modules.auth_tenancy.repositories.user_repository import UserRepository

# Lista explícita de símbolos exportados para importaciones limpias
__all__ = [
    "RoleRepository",
    "TenantRepository",
    "UserRepository",
]
