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
        Retorna los roles que ve un comercio: los globales del sistema más los
        suyos propios.

        Cuando el comercio tiene su **copia** de un rol global (Fase B de
        permisos: clone-on-write), la copia sustituye al estándar en el
        listado — si viajaran los dos, el dueño vería dos "Cajero" sin saber
        cuál asignar.
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
        roles = list(result.scalars().all())

        # La copia del comercio gana sobre el rol global del mismo nombre, y
        # nunca se devuelve el mismo nombre dos veces: una base que arrastre
        # copias duplicadas (por un reintento antiguo) no debe pintar dos
        # "Cajero" en la pantalla.
        visto: set[str] = set()
        salida: List[Role] = []
        for r in sorted(roles, key=lambda x: (x.tenant_id is None, str(x.id))):
            if r.name in visto:
                continue
            visto.add(r.name)
            salida.append(r)
        salida.sort(key=lambda r: r.name)
        return salida

    async def get_global_by_name(self, name: str) -> Optional[Role]:
        """
        Rol estándar del sistema (`tenant_id IS NULL`) por nombre. Es a donde
        vuelven los empleados cuando el dueño restablece un rol propio.
        """
        stmt = (
            select(Role)
            .where(Role.name == name, Role.tenant_id == None)  # noqa: E711
            .options(selectinload(Role.permissions))
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_own_by_name(
        self, name: str, tenant_id: uuid.UUID
    ) -> Optional[Role]:
        """
        La copia **propia** del comercio para ese nombre de rol, si ya existe.
        Sostiene la idempotencia del clone-on-write: un reintento no debe
        dejar dos roles con el mismo nombre en la misma tienda.
        """
        stmt = (
            select(Role)
            .where(Role.name == name, Role.tenant_id == tenant_id)
            .options(selectinload(Role.permissions))
            .order_by(Role.id.asc())
            .limit(1)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_permissions_by_codes(self, codes: List[str]) -> List[Permission]:
        """
        Permisos del catálogo cuyos códigos se piden. Lo que no exista no
        vuelve: el servicio compara cuántos pidió contra cuántos encontró.
        """
        if not codes:
            return []
        stmt = select(Permission).where(Permission.code.in_(codes))
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def clone_for_tenant(self, source: Role, tenant_id: uuid.UUID) -> Role:
        """
        Crea la copia de un rol global para un comercio, con los mismos
        permisos que tenía el estándar. Sin commit: la transacción la decide
        el servicio.
        """
        clone = Role(
            tenant_id=tenant_id,
            name=source.name,
            description=source.description,
        )
        clone.permissions = list(source.permissions)
        self.db.add(clone)
        await self.db.flush()
        return clone

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
