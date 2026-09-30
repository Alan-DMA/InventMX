# Importación del módulo UUID para identificación de recursos
import uuid
# Importación de tipos estáticos
from typing import List
# Importación de constructs de FastAPI
from fastapi import APIRouter, BackgroundTasks, Depends, status
from app.core.email.sender import send_email_quietly
# Importación de sesión asíncrona de SQLAlchemy
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de generador de sesión e inyector de dependencias
from app.core.database.session import get_db
# Importación de dependencias de seguridad y control RBAC
from app.core.security.deps import get_current_user, require_owner, require_permission
# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.user import User
# Importación de repositorios
from app.modules.auth_tenancy.repositories.role_repository import RoleRepository
from app.modules.auth_tenancy.services.role_service import RoleService
# Importación de esquemas Pydantic
from app.modules.auth_tenancy.schemas.role import (
    PermissionRead,
    RolePermissionsUpdate,
    RoleRead,
)
from app.modules.auth_tenancy.schemas.tenant import (
    PricingSettingsResponse,
    PricingSettingsUpdateRequest,
)
from app.modules.auth_tenancy.schemas.token import (
    RefreshTokenRequest,
    RegisterTenantRequest,
    TokenResponse,
)
from app.modules.auth_tenancy.schemas.user import (
    ChangePasswordRequest,
    LoginWithCodeRequest,
    PasswordRecoveryRequest,
    SetPasswordRequest,
    UpdateOperatingWarehouseRequest,
    UserCreate,
    UserLogin,
    UserRead,
    UserUpdate,
)
# Importación de servicios de lógica de negocio
from app.modules.auth_tenancy.services.auth_service import AuthService
from app.modules.auth_tenancy.services.login_code_service import LoginCodeService
from app.modules.auth_tenancy.services.tenant_service import TenantService
from app.modules.auth_tenancy.services.user_service import UserService

# Creación del router principal de autenticación y empleados
router = APIRouter(tags=["Autenticación, Empleados y Permisos RBAC"])


# =============================================================================
# ENDPOINTS DE AUTENTICACIÓN Y SESIÓN (/auth)
# =============================================================================

@router.post(
    "/auth/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar nuevo comercio (Tenant) y usuario dueño (Owner)",
)
async def register(
    data: RegisterTenantRequest,
    db: AsyncSession = Depends(get_db),
):
    """
    Registra un nuevo comercio con su usuario administrador dueño (Owner)
    en una única transacción atómica bajo el Plan Emprendedor por defecto.
    """
    service = AuthService(db)
    return await service.register_tenant_and_owner(data)


@router.post(
    "/auth/login",
    response_model=TokenResponse,
    status_code=status.HTTP_200_OK,
    summary="Iniciar sesión en el sistema",
)
async def login(
    login_data: UserLogin,
    db: AsyncSession = Depends(get_db),
):
    """
    Valida credenciales de usuario y genera Access Token (15 min) + Refresh Token (7 días).
    """
    service = AuthService(db)
    return await service.authenticate_user(login_data)


@router.post(
    "/auth/refresh",
    response_model=TokenResponse,
    status_code=status.HTTP_200_OK,
    summary="Refrescar sesión con Refresh Token",
)
async def refresh_token(
    data: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db),
):
    """
    Genera un nuevo Access Token a partir de un Refresh Token vigente sin requerir credenciales.
    """
    service = AuthService(db)
    return await service.refresh_access_token(data.refresh_token)


@router.get(
    "/auth/me",
    response_model=UserRead,
    status_code=status.HTTP_200_OK,
    summary="Obtener perfil del usuario autenticado",
)
async def get_me(current_user: User = Depends(get_current_user)):
    """
    Retorna la información del usuario en sesión activa, incluyendo su rol y lista de permisos.
    """
    return current_user


@router.post(
    "/auth/change-password",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Cambiar la contraseña del usuario en sesión",
)
async def change_password(
    data: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Exige la contraseña actual (400 si no coincide); la nueva lleva mínimo 8
    caracteres. La sesión sigue abierta (D9).
    """
    service = AuthService(db)
    await service.change_password(data, current_user)


@router.post(
    "/auth/password-recovery",
    status_code=status.HTTP_202_ACCEPTED,
    summary="¿Olvidaste tu contraseña? Envía un código al correo",
)
async def request_password_recovery(
    data: PasswordRecoveryRequest,
    background: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    """
    Si el correo tiene cuenta, le llega un código de un solo uso (30 min).
    Responde siempre lo mismo, y el correo sale después de responder: ni el
    texto ni el tiempo de respuesta revelan qué correos están registrados.
    """
    message = await LoginCodeService(db).request_self_recovery(data.email)
    if message is not None:
        background.add_task(send_email_quietly, message)
    return {"message": "Si el correo tiene una cuenta en Nexus, te enviamos un código. Revisa tu bandeja y la de spam."}


@router.post(
    "/auth/login-with-code",
    response_model=TokenResponse,
    status_code=status.HTTP_200_OK,
    summary="Entrar con el código de un solo uso",
)
async def login_with_code(
    data: LoginWithCodeRequest,
    db: AsyncSession = Depends(get_db),
):
    """
    El código sustituye a la contraseña una vez. La sesión sale con
    `user.must_change_password = true`: hasta poner una nueva sólo responden
    `/auth/me` y `/auth/set-password` (403 `PASSWORD_CHANGE_REQUIRED` en lo demás).
    """
    return await AuthService(db).login_with_code(data.email, data.code)


@router.post(
    "/auth/set-password",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Poner contraseña nueva tras entrar con un código",
)
async def set_password(
    data: SetPasswordRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Sólo con el cambio pendiente (400 si no); invalida cualquier otro código vigente."""
    await AuthService(db).set_new_password(data.new_password, current_user)


@router.patch(
    "/auth/me/warehouse",
    response_model=UserRead,
    status_code=status.HTTP_200_OK,
    summary="Cambiar el almacén operativo del usuario en sesión",
)
async def update_my_warehouse(
    data: UpdateOperatingWarehouseRequest,
    current_user: User = Depends(require_permission("settings.manage_store")),
    db: AsyncSession = Depends(get_db),
):
    """
    Actualiza en qué almacén está operando el usuario autenticado hoy.

    Requiere `settings.manage_store`, la misma puerta que la pantalla "Dónde
    opero": el almacén operativo acota lo que un empleado ve (aislamiento por
    almacén, W1), así que cambiárselo solo lo dejaría leer otra sucursal. A un
    empleado se lo asigna el dueño desde `PUT /users/{id}`.
    """
    service = UserService(db)
    return await service.update_operating_warehouse(data.warehouse_id, current_user)


# =============================================================================
# ENDPOINTS DE CONFIGURACIÓN DE PRECIOS DEL COMERCIO (/tenants/me)
# =============================================================================

@router.get(
    "/tenants/me/pricing-settings",
    response_model=PricingSettingsResponse,
    status_code=status.HTTP_200_OK,
    summary="Consultar configuración de precios del comercio",
)
async def get_pricing_settings(
    current_user: User = Depends(require_permission("settings.manage_store")),
):
    """
    Retorna el margen máximo sugerido configurado para el comercio, usado
    como piso del "precio máximo sugerido" por producto.
    """
    return current_user.tenant


@router.patch(
    "/tenants/me/pricing-settings",
    response_model=PricingSettingsResponse,
    status_code=status.HTTP_200_OK,
    summary="Actualizar margen máximo sugerido del comercio",
)
async def update_pricing_settings(
    data: PricingSettingsUpdateRequest,
    current_user: User = Depends(require_permission("settings.manage_store")),
    db: AsyncSession = Depends(get_db),
):
    """
    Actualiza el margen máximo sugerido (%) sobre costo del comercio en sesión.
    """
    service = TenantService(db)
    return await service.update_pricing_settings(data.max_margin_percent, current_user)


# =============================================================================
# ENDPOINTS DE GESTIÓN DE EMPLEADOS (/users) - HU-03 / CU-03
# =============================================================================

@router.get(
    "/users",
    response_model=List[UserRead],
    status_code=status.HTTP_200_OK,
    summary="Listar todos los empleados del comercio",
)
async def list_employees(
    current_user: User = Depends(require_permission("settings.manage_users")),
    db: AsyncSession = Depends(get_db),
):
    """
    Retorna el listado de empleados pertenecientes al comercio actual, aislados por RLS.
    Requiere permiso 'settings.manage_users' o rol OWNER.
    """
    service = UserService(db)
    return await service.list_employees(current_user)


@router.post(
    "/users",
    response_model=UserRead,
    status_code=status.HTTP_201_CREATED,
    summary="Crear un nuevo empleado en el comercio",
)
async def create_employee(
    data: UserCreate,
    current_user: User = Depends(require_permission("settings.manage_users")),
    db: AsyncSession = Depends(get_db),
):
    """
    Crea un nuevo empleado (Cajero, Almacenista, Administrador) en el comercio.
    Valida automáticamente los límites de usuarios del plan SaaS (Emprendedor: 2, Comercio: 5, Corporativo: 15).
    """
    service = UserService(db)
    return await service.create_employee(data, current_user)


@router.get(
    "/users/{user_id}",
    response_model=UserRead,
    status_code=status.HTTP_200_OK,
    summary="Consultar detalle de un empleado específico",
)
async def get_employee(
    user_id: uuid.UUID,
    current_user: User = Depends(require_permission("settings.manage_users")),
    db: AsyncSession = Depends(get_db),
):
    """
    Retorna los datos de un empleado por su ID si pertenece al mismo comercio.
    """
    service = UserService(db)
    return await service.get_employee_by_id(user_id, current_user)


@router.put(
    "/users/{user_id}",
    response_model=UserRead,
    status_code=status.HTTP_200_OK,
    summary="Actualizar datos de un empleado",
)
async def update_employee(
    user_id: uuid.UUID,
    data: UserUpdate,
    current_user: User = Depends(require_permission("settings.manage_users")),
    db: AsyncSession = Depends(get_db),
):
    """
    Modifica el nombre, contraseña o estado activo de un empleado.
    """
    service = UserService(db)
    return await service.update_employee(user_id, data, current_user)


@router.patch(
    "/users/{user_id}/status",
    response_model=UserRead,
    status_code=status.HTTP_200_OK,
    summary="Activar o desactivar un empleado",
)
async def toggle_employee_status(
    user_id: uuid.UUID,
    current_user: User = Depends(require_permission("settings.manage_users")),
    db: AsyncSession = Depends(get_db),
):
    """
    Alterna el estado activo de un empleado. Impide desactivar al usuario OWNER.
    """
    service = UserService(db)
    return await service.toggle_employee_status(user_id, current_user)


@router.delete(
    "/users/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Eliminar un empleado del comercio",
)
async def delete_employee(
    user_id: uuid.UUID,
    current_user: User = Depends(require_permission("settings.manage_users")),
    db: AsyncSession = Depends(get_db),
):
    """
    Elimina físicamente a un empleado del sistema. Impide la auto-eliminación o eliminar al dueño.
    """
    service = UserService(db)
    await service.delete_employee(user_id, current_user)


# =============================================================================
# ENDPOINTS DE ROLES Y PERMISOS (/roles & /permissions)
# =============================================================================

@router.get(
    "/roles",
    response_model=List[RoleRead],
    status_code=status.HTTP_200_OK,
    summary="Listar roles disponibles para asignar",
)
async def list_roles(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Retorna los roles estándar del sistema (ADMIN, CASHIER, WAREHOUSE) y personalizados.
    """
    repo = RoleRepository(db)
    return await repo.get_all_roles(current_user.tenant_id)


@router.put(
    "/roles/{role_id}/permissions",
    response_model=RoleRead,
    status_code=status.HTTP_200_OK,
    summary="Personalizar los permisos de un rol dentro del comercio",
)
async def update_role_permissions(
    role_id: uuid.UUID,
    data: RolePermissionsUpdate,
    current_user: User = Depends(require_owner),
    db: AsyncSession = Depends(get_db),
):
    """
    Deja el rol con exactamente los permisos indicados (Fase B).

    La primera vez que se personaliza un rol del sistema, el comercio se queda
    con su **propia copia** y los empleados que lo tenían pasan a ella; las
    siguientes ediciones ya actúan sobre esa copia. El rol Dueño no se toca y
    ningún rol se queda sin `inventory.view`.
    """
    service = RoleService(db)
    return await service.update_permissions(role_id, data.permissions, current_user)


@router.delete(
    "/roles/{role_id}",
    response_model=RoleRead,
    status_code=status.HTTP_200_OK,
    summary="Restablecer un rol personalizado al estándar del sistema",
)
async def reset_role(
    role_id: uuid.UUID,
    current_user: User = Depends(require_owner),
    db: AsyncSession = Depends(get_db),
):
    """
    Borra la copia del comercio y devuelve a sus empleados al rol estándar.
    Responde con el rol estándar al que volvieron.
    """
    service = RoleService(db)
    return await service.reset_role(role_id, current_user)


@router.get(
    "/permissions",
    response_model=List[PermissionRead],
    status_code=status.HTTP_200_OK,
    summary="Listar catálogo maestro de permisos del sistema",
)
async def list_permissions(
    current_user: User = Depends(require_permission("settings.manage_users")),
    db: AsyncSession = Depends(get_db),
):
    """
    Retorna el catálogo completo de permisos atómicos del sistema RBAC.
    """
    repo = RoleRepository(db)
    return await repo.get_all_permissions()
