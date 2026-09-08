# Importación de UUID para identificación única
import uuid
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de excepciones de negocio
from app.core.exceptions.base import (
    ConflictException,
    NotFoundException,
    TenantLockedException,
    UnauthorizedException,
)
# Importación de utilidades de seguridad JWT y hash
from app.core.security.jwt import create_access_token, create_refresh_token, decode_token
from app.core.security.password import get_password_hash, verify_password
from app.core.database.session import set_tenant_context
# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan, TenantStatus
from app.modules.auth_tenancy.domain.user import User
# Importación de repositorios de datos
from app.modules.auth_tenancy.repositories.tenant_repository import TenantRepository
from app.modules.auth_tenancy.repositories.user_repository import UserRepository
# Importación de esquemas Pydantic
from app.modules.auth_tenancy.schemas.token import (
    RegisterTenantRequest,
    TokenResponse,
)
from app.modules.auth_tenancy.schemas.user import UserLogin


class AuthService:
    """
    Servicio de autenticación, registro de nuevos comercios y emisión de tokens.
    """

    def __init__(self, db: AsyncSession):
        # Inyección de la sesión asíncrona de base de datos
        self.db = db
        # Instanciación del repositorio de comercios (Tenant)
        self.tenant_repo = TenantRepository(db)
        # Instanciación del repositorio de usuarios (User)
        self.user_repo = UserRepository(db)

    async def register_tenant_and_owner(self, data: RegisterTenantRequest) -> TokenResponse:
        """
        Registra un nuevo comercio (Tenant) y su usuario dueño (Owner)
        en una única transacción atómica.
        """
        # 1. Verificar si el slug ya existe en el sistema
        existing_tenant = await self.tenant_repo.get_by_slug(data.slug)
        if existing_tenant:
            raise ConflictException(f"El slug de tienda '{data.slug}' ya se encuentra registrado.")

        # 2. Verificar si el email del dueño ya existe
        existing_user = await self.user_repo.get_by_email_global(data.email)
        if existing_user:
            raise ConflictException(f"El correo electrónico '{data.email}' ya tiene una cuenta activa.")

        # 3. Crear el Tenant con Plan Emprendedor por defecto
        tenant = await self.tenant_repo.create(
            name=data.store_name,
            slug=data.slug,
            plan_id=TenantPlan.EMPRENDEDOR,
            rfc=data.rfc,
        )

        # 4. Asignar el rol OWNER global por defecto
        owner_role_id = uuid.UUID("a0000000-0000-0000-0000-000000000001")

        # 5. Inyectar contexto para RLS antes de insertar el usuario
        await set_tenant_context(self.db, tenant.id)

        # 6. Crear el usuario Owner con contraseña hasheada
        user = await self.user_repo.create(
            tenant_id=tenant.id,
            email=data.email,
            hashed_password=get_password_hash(data.password),
            full_name=data.full_name,
            role_id=owner_role_id,
            is_active=True,
        )

        # Confirmar la transacción
        await self.db.commit()

        # Re-inyectar contexto tras commit para recargar relaciones
        await set_tenant_context(self.db, tenant.id)
        user_full = await self.user_repo.get_by_id(user.id)

        # Generar tokens con estado del tenant
        access_token = create_access_token(
            subject=user.id,
            tenant_id=tenant.id,
            role="OWNER",
            tenant_status=tenant.status.value,
        )
        refresh_token = create_refresh_token(
            subject=user.id,
            tenant_id=tenant.id,
        )

        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="bearer",
            user=user_full,
            tenant=tenant,
        )

    async def authenticate_user(self, login_data: UserLogin) -> TokenResponse:
        """
        Autentica a un usuario por email y contraseña, emitiendo sus tokens de acceso.
        """
        # Buscar usuario a nivel global
        user = await self.user_repo.get_by_email_global(login_data.email)
        if not user or not verify_password(login_data.password, user.hashed_password):
            raise UnauthorizedException("Correo electrónico o contraseña incorrectos.")

        # Validar si el usuario está activo
        if not user.is_active:
            raise UnauthorizedException("Tu cuenta se encuentra desactivada. Contacta al administrador.")

        tenant = user.tenant
        if not tenant:
            raise NotFoundException("Comercio no encontrado.")

        # Validar estado del tenant (Hard lock)
        if tenant.status == TenantStatus.HARD_LOCK:
            raise TenantLockedException(
                message="Tu cuenta está bloqueada por falta de pago. Por favor regulariza tu suscripción.",
                lock_type="HARD_LOCK",
            )

        # Inyectar contexto RLS para la sesión
        await set_tenant_context(self.db, tenant.id)

        # Determinar nombre del rol
        role_name = user.role.name if user.role else "CASHIER"
        
        # Generar tokens
        access_token = create_access_token(
            subject=user.id,
            tenant_id=tenant.id,
            role=role_name,
            tenant_status=tenant.status.value,
        )
        refresh_token = create_refresh_token(
            subject=user.id,
            tenant_id=tenant.id,
        )

        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="bearer",
            user=user,
            tenant=tenant,
        )

    async def refresh_access_token(self, refresh_token: str) -> TokenResponse:
        """
        Renueva el token de acceso utilizando un refresh token vigente.
        """
        # Decodificar el token de refresco
        payload = decode_token(refresh_token)
        if payload.get("type") != "refresh":
            raise UnauthorizedException("Tipo de token inválido para refrescar sesión.")

        user_id_str = payload.get("sub")
        if not user_id_str:
            raise UnauthorizedException("Payload del token no contiene identificador de usuario.")

        tenant_id_str = payload.get("tenant_id")
        if tenant_id_str:
            await set_tenant_context(self.db, tenant_id_str)

        user = await self.user_repo.get_by_id(uuid.UUID(user_id_str))
        if not user or not user.is_active:
            raise UnauthorizedException("Usuario inválido o inactivo.")

        tenant = user.tenant
        if not tenant or tenant.status == TenantStatus.HARD_LOCK:
            raise TenantLockedException(
                message="Tu cuenta está bloqueada por falta de pago.",
                lock_type="HARD_LOCK",
            )

        role_name = user.role.name if user.role else "CASHIER"
        new_access_token = create_access_token(
            subject=user.id,
            tenant_id=tenant.id,
            role=role_name,
            tenant_status=tenant.status.value,
        )
        new_refresh_token = create_refresh_token(
            subject=user.id,
            tenant_id=tenant.id,
        )

        return TokenResponse(
            access_token=new_access_token,
            refresh_token=new_refresh_token,
            token_type="bearer",
            user=user,
            tenant=tenant,
        )
