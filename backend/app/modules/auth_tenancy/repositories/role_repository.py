# Importación del módulo UUID para identificación de registros
import uuid
# Importación de tipos para anotaciones estáticas
from typing import List, Optional
# Importación de constructs de consulta en SQLAlchemy
from sqlalchemy import select
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession
# Importación de estrategia de carga eagerly para relaciones
from sqlalchemy.orm import selectinload

# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.permission import Permission
from app.modules.auth_tenancy.domain.role import Role


class RoleRepository:
    """
    Repositorio de acceso a datos para Roles y Permisos RBAC.
    Permite consultar roles del sistema, roles personalizados de tenant y catálogo de permisos.
    """

    def __init__(self, db: AsyncSession):
        # Inyección de la sesión asíncrona activa de base de datos
        self.db = db

    async def get_all_roles(self, tenant_id: Optional[uuid.UUID] = None) -> List[Role]:
        """
        Retorna todos los roles globales (tenant_id IS NULL) más los roles específicos del tenant.
        Carga de forma eficiente la relación de permisos mediante selectinload.
        """
        # Construcción de la sentencia select con filtro condicional
        stmt = (
            select(Role)
            .where(
                (Role.tenant_id == None) | (Role.tenant_id == tenant_id)  # noqa: E711
            )
            .options(selectinload(Role.permissions))  # Carga anticipada de permisos
            .order_by(Role.name.asc())  # Orden alfabético
        )
        # Ejecución asíncrona de la consulta
        result = await self.db.execute(stmt)
        # Retorno de lista de entidades Role
        return list(result.scalars().all())

    async def get_by_id(self, role_id: uuid.UUID) -> Optional[Role]:
        """
        Consulta un rol específico por su identificador único UUID.
        """
        # Sentencia select filtrando por clave primaria
        stmt = (
            select(Role)
            .where(Role.id == role_id)
            .options(selectinload(Role.permissions))  # Incluir permisos asociados
        )
        # Ejecutar y obtener único resultado o None
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_name(self, name: str, tenant_id: Optional[uuid.UUID] = None) -> Optional[Role]:
        """
        Busca un rol por su nombre (ej. 'CASHIER', 'ADMIN', 'OWNER').
        """
        # Sentencia select buscando por coincidencia exacta de nombre
        stmt = (
            select(Role)
            .where(
                Role.name == name,
                (Role.tenant_id == None) | (Role.tenant_id == tenant_id),  # noqa: E711
            )
            .options(selectinload(Role.permissions))
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_all_permissions(self) -> List[Permission]:
        """
        Retorna el catálogo completo de permisos atómicos del sistema.
        """
        # Sentencia select ordenada por código de permiso
        stmt = select(Permission).order_by(Permission.code.asc())
        # Ejecutar consulta
        result = await self.db.execute(stmt)
        # Retornar lista de permisos
        return list(result.scalars().all())
