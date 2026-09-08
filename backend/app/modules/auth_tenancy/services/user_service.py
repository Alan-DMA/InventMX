# Importación de UUID para tipado y validación de identificadores
import uuid
# Importación de tipos estáticos
from typing import Dict, List, Optional
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de excepciones de negocio del sistema
from app.core.exceptions.base import (
    BadRequestException,
    ConflictException,
    ForbiddenException,
    NotFoundException,
)
# Importación de utilidades criptográficas
from app.core.security.password import get_password_hash
# Importación de inyector de contexto RLS
from app.core.database.session import set_tenant_context
# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.tenant import TenantPlan
from app.modules.auth_tenancy.domain.user import User
# Importación de repositorios de datos
from app.modules.auth_tenancy.repositories.role_repository import RoleRepository
from app.modules.auth_tenancy.repositories.user_repository import UserRepository
# Importación de esquemas Pydantic para validación de entrada
from app.modules.auth_tenancy.schemas.user import UserCreate, UserUpdate

# Mapeo de límites de usuarios por plan SaaS (Const. Art. 6.1 / Doc. Maestro Sec. 3)
PLAN_USER_LIMITS: Dict[TenantPlan, int] = {
    TenantPlan.EMPRENDEDOR: 2,   # Plan Emprendedor ($199 MXN): Máximo 2 usuarios
    TenantPlan.COMERCIO: 5,       # Plan Comercio ($399 MXN): Máximo 5 usuarios
    TenantPlan.CORPORATIVO: 15,   # Plan Corporativo ($699 MXN): Máximo 15 usuarios
}


class UserService:
    """
    Servicio de lógica de negocio para la gestión de empleados y asignación de roles RBAC.
    """

    def __init__(self, db: AsyncSession):
        # Inyección de la sesión asíncrona de SQLAlchemy
        self.db = db
        # Instanciación del repositorio de usuarios
        self.user_repo = UserRepository(db)
        # Instanciación del repositorio de roles
        self.role_repo = RoleRepository(db)

    async def list_employees(self, current_user: User) -> List[User]:
        """
        Retorna la lista completa de empleados del comercio autenticado.
        """
        # Asegurar contexto RLS en PostgreSQL
        await set_tenant_context(self.db, current_user.tenant_id)
        # Consultar empleados del tenant
        return await self.user_repo.list_by_tenant(current_user.tenant_id)

    async def get_employee_by_id(self, user_id: uuid.UUID, current_user: User) -> User:
        """
        Obtiene el detalle de un empleado verificando pertenencia al mismo tenant.
        """
        # Asegurar contexto RLS en PostgreSQL
        await set_tenant_context(self.db, current_user.tenant_id)
        # Buscar usuario por ID
        user = await self.user_repo.get_by_id(user_id)
        # Si no existe o pertenece a otro tenant (filtrado por RLS), lanzar 404
        if not user or user.tenant_id != current_user.tenant_id:
            raise NotFoundException(f"Empleado con ID '{user_id}' no encontrado.")
        return user

    async def create_employee(self, data: UserCreate, current_user: User) -> User:
        """
        Crea un nuevo empleado validando los límites de usuarios del plan contratado.
        """
        # Obtener el plan del tenant actual
        tenant = current_user.tenant
        plan_id = tenant.plan_id
        # Obtener el límite máximo de usuarios permitido para el plan
        max_allowed_users = PLAN_USER_LIMITS.get(plan_id, 2)

        # Contar usuarios activos actuales del comercio
        active_users_count = await self.user_repo.count_active_by_tenant(current_user.tenant_id)

        # Validación estricta de cupo por plan SaaS
        if active_users_count >= max_allowed_users:
            raise BadRequestException(
                f"Has alcanzado el límite máximo de {max_allowed_users} usuarios para tu Plan {plan_id.value}. "
                "Actualiza tu plan de suscripción para habilitar más accesos de empleados."
            )

        # Validar que el rol a asignar exista
        role = await self.role_repo.get_by_id(data.role_id)
        if not role:
            raise NotFoundException(f"El rol con ID '{data.role_id}' no existe en el sistema.")

        # Impedir crear otro usuario OWNER adicional si no es el dueño original
        if role.name == "OWNER" and current_user.role.name != "OWNER":
            raise ForbiddenException("Solo el dueño del comercio puede designar roles de tipo OWNER.")

        # Verificar unicidad de email dentro del tenant o global
        existing_user = await self.user_repo.get_by_email_global(data.email)
        if existing_user:
            raise ConflictException(f"El correo '{data.email}' ya se encuentra registrado en el sistema.")

        # Inyectar contexto RLS para la inserción
        await set_tenant_context(self.db, current_user.tenant_id)

        # Generar hash de contraseña con bcrypt
        hashed_pwd = get_password_hash(data.password)

        # Crear el usuario a través del repositorio
        new_user = await self.user_repo.create(
            tenant_id=current_user.tenant_id,
            email=data.email,
            hashed_password=hashed_pwd,
            full_name=data.full_name,
            role_id=data.role_id,
            is_active=True,
        )

        # Persistir la transacción
        await self.db.commit()

        # Recargar con relaciones y contexto RLS activo
        await set_tenant_context(self.db, current_user.tenant_id)
        return await self.user_repo.get_by_id(new_user.id)

    async def update_employee(self, user_id: uuid.UUID, data: UserUpdate, current_user: User) -> User:
        """
        Actualiza los datos de un empleado (nombre, contraseña, estado).
        """
        # Obtener el empleado verificando pertenencia
        employee = await self.get_employee_by_id(user_id, current_user)

        # Hashear nueva contraseña si fue provista
        hashed_pwd = get_password_hash(data.password) if data.password else None

        # Actualizar campos
        updated_user = await self.user_repo.update(
            user=employee,
            full_name=data.full_name,
            hashed_password=hashed_pwd,
            is_active=data.is_active,
        )

        # Persistir cambios en base de datos
        await self.db.commit()

        # Recargar con relaciones
        await set_tenant_context(self.db, current_user.tenant_id)
        return await self.user_repo.get_by_id(updated_user.id)

    async def toggle_employee_status(self, user_id: uuid.UUID, current_user: User) -> User:
        """
        Invierte el estado activo/inactivo de un empleado.
        Impide desactivar al usuario dueño (OWNER).
        """
        # Obtener empleado
        employee = await self.get_employee_by_id(user_id, current_user)

        # Protección: No se puede desactivar al usuario OWNER
        if employee.role and employee.role.name == "OWNER":
            raise BadRequestException("No es posible desactivar la cuenta principal del dueño (OWNER).")

        # Invertir estado
        new_status = not employee.is_active

        # Actualizar en repositorio
        await self.user_repo.update(user=employee, is_active=new_status)
        # Confirmar transacción
        await self.db.commit()

        # Recargar entidad
        await set_tenant_context(self.db, current_user.tenant_id)
        return await self.user_repo.get_by_id(employee.id)

    async def delete_employee(self, user_id: uuid.UUID, current_user: User) -> None:
        """
        Elimina a un empleado del sistema.
        Impide la auto-eliminación o eliminar al dueño del comercio.
        """
        # Protección: Evitar auto-eliminación
        if user_id == current_user.id:
            raise BadRequestException("No puedes eliminar tu propia cuenta de usuario en sesión activa.")

        # Obtener empleado
        employee = await self.get_employee_by_id(user_id, current_user)

        # Protección: Impedir eliminar cuenta OWNER
        if employee.role and employee.role.name == "OWNER":
            raise BadRequestException("La cuenta principal del dueño (OWNER) no puede ser eliminada.")

        # Eliminar registro
        await self.user_repo.delete(employee)
        # Confirmar transacción
        await self.db.commit()
