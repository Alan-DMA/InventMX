# Importación de UUID para identificación única de entidades
import uuid
# Importación de tipos estáticos para anotación
from typing import List, Optional
# Importación de operadores de consulta y funciones de agregación
from sqlalchemy import func, select, update, delete
# Importación de la sesión asíncrona de SQLAlchemy
from sqlalchemy.ext.asyncio import AsyncSession
# Importación de estrategia de carga anticipada para relaciones
from sqlalchemy.orm import selectinload

# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.role import Role
from app.modules.auth_tenancy.domain.user import User


class UserRepository:
    """
    Repositorio de acceso a datos para la entidad User.
    Encapsula consultas sobre usuarios, respetando el contexto RLS.
    """

    def __init__(self, db: AsyncSession):
        # Almacenamiento de la referencia a la sesión de base de datos
        self.db = db

    async def get_by_id(self, user_id: uuid.UUID) -> Optional[User]:
        """
        Obtiene un usuario por su UUID, cargando su rol, permisos y comercio.
        """
        # Sentencia select filtrando por ID de usuario con eager-loading y refresco forzado
        stmt = (
            select(User)
            .where(User.id == user_id)
            .options(
                selectinload(User.role).selectinload(Role.permissions),
                selectinload(User.tenant),
            )
            .execution_options(populate_existing=True)
        )
        # Ejecutar consulta asíncrona
        result = await self.db.execute(stmt)
        # Retornar usuario o None si no existe
        return result.scalar_one_or_none()

    async def get_by_email_and_tenant(self, email: str, tenant_id: uuid.UUID) -> Optional[User]:
        """
        Busca un usuario por correo dentro de un Tenant específico.
        """
        # Sentencia select filtrando por email y tenant_id
        stmt = (
            select(User)
            .where(User.email == email, User.tenant_id == tenant_id)
            .options(
                selectinload(User.role).selectinload(Role.permissions),
                selectinload(User.tenant),
            )
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_email_global(self, email: str) -> Optional[User]:
        """
        Busca un usuario por correo a nivel global (usado principalmente en Login).
        """
        # Sentencia select buscando coincidencia global de email
        stmt = (
            select(User)
            .where(User.email == email)
            .options(
                selectinload(User.role).selectinload(Role.permissions),
                selectinload(User.tenant),
            )
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def list_by_tenant(self, tenant_id: uuid.UUID) -> List[User]:
        """
        Retorna la lista de todos los empleados pertenecientes a un comercio.
        """
        # Sentencia select filtrando por tenant_id
        stmt = (
            select(User)
            .where(User.tenant_id == tenant_id)
            .options(
                selectinload(User.role).selectinload(Role.permissions),
                selectinload(User.tenant),
            )
            .order_by(User.created_at.asc())
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def count_active_by_tenant(self, tenant_id: uuid.UUID) -> int:
        """
        Cuenta el número de usuarios activos de un comercio para validación de límites de plan.
        """
        # Sentencia de conteo COUNT(*) filtrada por tenant y estado activo
        stmt = (
            select(func.count(User.id))
            .where(User.tenant_id == tenant_id, User.is_active == True)  # noqa: E712
        )
        result = await self.db.execute(stmt)
        return result.scalar() or 0

    async def create(
        self,
        tenant_id: uuid.UUID,
        email: str,
        hashed_password: str,
        full_name: str,
        role_id: uuid.UUID,
        is_active: bool = True,
    ) -> User:
        """
        Crea e inserta un nuevo usuario en la base de datos.
        """
        # Instanciación del modelo User con sus atributos iniciales
        user = User(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            email=email,
            hashed_password=hashed_password,
            full_name=full_name,
            role_id=role_id,
            is_active=is_active,
        )
        # Registro en la sesión activa
        self.db.add(user)
        # Flush para enviar los datos a PostgreSQL y validar constraints
        await self.db.flush()
        return user

    async def update(
        self,
        user: User,
        full_name: Optional[str] = None,
        email: Optional[str] = None,
        role_id: Optional[uuid.UUID] = None,
        hashed_password: Optional[str] = None,
        is_active: Optional[bool] = None,
    ) -> User:
        """
        Actualiza los campos proporcionados de un usuario existente.
        """
        if full_name is not None:
            user.full_name = full_name
        if email is not None:
            user.email = email
        if role_id is not None:
            user.role_id = role_id
        if hashed_password is not None:
            user.hashed_password = hashed_password
        if is_active is not None:
            user.is_active = is_active

        # Marcar para actualización y flush
        await self.db.flush()
        return user

    async def delete(self, user: User) -> None:
        """
        Elimina físicamente un usuario de la base de datos.
        """
        await self.db.delete(user)
        await self.db.flush()
