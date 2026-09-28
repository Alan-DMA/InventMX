# Importación de UUID para identificación única
import uuid
from datetime import datetime, timezone
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de excepciones de negocio
from app.core.exceptions.base import (
    BadRequestException,
    ConflictException,
    NotFoundException,
    UnauthorizedException,
)
# Importación de utilidades de seguridad JWT y hash
from app.core.security.jwt import create_access_token, create_refresh_token, decode_token
from app.core.security.password import get_password_hash, verify_password
from app.core.database.session import set_tenant_context
# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan
from app.modules.auth_tenancy.domain.user import User
# Importación de repositorios de datos
from app.modules.auth_tenancy.repositories.tenant_repository import TenantRepository
from app.modules.auth_tenancy.repositories.user_repository import UserRepository
# Importación de esquemas Pydantic
from app.modules.auth_tenancy.schemas.token import (
    RegisterTenantRequest,
    TokenResponse,
)
from app.modules.auth_tenancy.schemas.user import ChangePasswordRequest, UserLogin
from app.modules.auth_tenancy.services.login_code_service import LOGIN_CODE_REJECTED, LoginCodeService


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

        # Un comercio en HARD_LOCK SÍ inicia sesión (P13, Sep 2026): la
        # renovación con Google Play se hace desde la app, así que tiene que
        # poder entrar. Su token lleva HARD_LOCK y el middleware sólo le deja
        # ver su suscripción (402 en todo lo demás).

        return await self._open_session(user)

    async def _open_session(self, user: User, must_change_password: bool = False) -> TokenResponse:
        """
        Registra el acceso y emite los tokens. Con `must_change_password` (entró
        con un código de un solo uso, P16) la API sólo le deja poner contraseña nueva.
        """
        tenant = user.tenant
        # Inyectar contexto RLS para la sesión
        await set_tenant_context(self.db, tenant.id)

        # Última actividad del comercio para el panel de plataforma (Fase 1)
        user.last_login_at = datetime.now(timezone.utc)
        if must_change_password:
            user.must_change_password = True
        await self.db.commit()

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

    async def login_with_code(self, email: str, code: str) -> TokenResponse:
        """
        Entra con el código de un solo uso que le llegó al correo (P16). Mismo
        mensaje para correo desconocido, código equivocado o vencido: no delata
        qué correos existen.
        """
        user = await self.user_repo.get_by_email_global(email.strip())
        if not user or not user.is_active or not user.tenant:
            raise UnauthorizedException(LOGIN_CODE_REJECTED)
        if not await LoginCodeService(self.db).consume(user, code):
            raise UnauthorizedException(LOGIN_CODE_REJECTED)
        return await self._open_session(user, must_change_password=True)

    async def set_new_password(self, new_password: str, current_user: User) -> None:
        """
        Contraseña nueva tras entrar con un código (P16): no pide la actual,
        por eso sólo vale mientras la cuenta esté marcada para cambiarla.
        """
        if not current_user.must_change_password:
            raise BadRequestException(
                "Tu cuenta no tiene un cambio de contraseña pendiente: usa \"Cambiar contraseña\"."
            )
        await set_tenant_context(self.db, current_user.tenant_id)
        await self.user_repo.update(user=current_user, hashed_password=get_password_hash(new_password))
        current_user.must_change_password = False
        await LoginCodeService(self.db).invalidate_all(current_user.id)
        await self.db.commit()

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
        if not tenant:
            raise NotFoundException("Comercio no encontrado.")

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

    async def change_password(self, data: ChangePasswordRequest, current_user: User) -> None:
        """
        Cambia la contraseña de quien está en sesión (D9). Exige la actual para
        que un teléfono desbloqueado en el mostrador no baste para quedarse con
        la cuenta. Los tokens vigentes siguen sirviendo: la sesión no se cierra.
        """
        if not verify_password(data.current_password, current_user.hashed_password):
            raise BadRequestException("La contraseña actual no es correcta.")

        await set_tenant_context(self.db, current_user.tenant_id)
        await self.user_repo.update(
            user=current_user,
            hashed_password=get_password_hash(data.new_password),
        )
        await self.db.commit()
