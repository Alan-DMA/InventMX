from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text
from pydantic import BaseModel
import jwt
from uuid import UUID
from typing import Optional

from app.core.database import get_db
from app.core.rls import set_current_tenant
from app.core.security import (
    verify_password, get_password_hash, create_access_token, create_refresh_token
)
from app.core.config import settings
from app.schemas.auth import (
    TenantRegister, UserLogin, LoginResponse, Token, TenantResponse, UserResponse
)
from app.models.models import Tenant, Role, User, Permission, role_permissions

router = APIRouter()

@router.post("/register", response_model=LoginResponse, status_code=status.HTTP_201_CREATED)
async def register_tenant(payload: TenantRegister, db: AsyncSession = Depends(get_db)):
    """
    Registra un nuevo comercio (Tenant) junto con sus roles por defecto 
    y el usuario administrador principal.
    """
    # 1. Verificar si el email o username ya existen globalmente
    # (Como es registro global, RLS debe estar inactivo o consultamos omitiendo el tenant)
    # Por seguridad, limpiamos el tenant_id en la sesión para poder consultar globalmente
    await db.execute(text("SELECT set_config('app.current_tenant', '', false)"))
    
    email_check = await db.execute(
        select(User).where(User.email == payload.admin_user.email)
    )
    if email_check.scalars().first():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El correo electrónico ya está registrado."
        )

    # 2. Crear el Tenant
    new_tenant = Tenant(
        name=payload.name,
        preferred_payment_method=payload.preferred_payment_method,
        payment_instructions=payload.payment_instructions,
        plan_id=payload.plan_id
    )
    db.add(new_tenant)
    await db.flush() # Genera el ID del tenant sin hacer commit

    # 3. Configurar contexto del tenant para las siguientes operaciones RLS
    await db.execute(
        text("SELECT set_config('app.current_tenant', :tenant_id, false)"),
        {"tenant_id": str(new_tenant.id)}
    )

    # 4. Crear los Roles por defecto para este Tenant
    role_owner = Role(tenant_id=new_tenant.id, name="TENANT_OWNER", description="Propietario del comercio con acceso total")
    role_manager = Role(tenant_id=new_tenant.id, name="MANAGER", description="Administrador del comercio, gestiona stock y personal")
    role_cashier = Role(tenant_id=new_tenant.id, name="CASHIER", description="Cajero encargado del checkout rápido y arqueo")
    role_salesperson = Role(tenant_id=new_tenant.id, name="SALESPERSON", description="Vendedor enfocado en registro rápido de ventas")

    db.add_all([role_owner, role_manager, role_cashier, role_salesperson])
    await db.flush()

    # 5. Copiar los Permisos Globales y asignarlos al rol OWNER y otros
    perms_result = await db.execute(select(Permission))
    all_perms = perms_result.scalars().all()
    
    # OWNER tiene todo
    owner_association = [{"role_id": role_owner.id, "permission_id": p.id} for p in all_perms]
    # MANAGER tiene todo menos gestión de SaaS
    manager_association = [{"role_id": role_manager.id, "permission_id": p.id} for p in all_perms if p.name != "saas.manage"]
    # CASHIER
    cashier_names = ["inventario.ver", "ventas.ver", "ventas.crear", "ventas.cobrar", "caja.ver", "caja.arquear", "caja.movimientos"]
    cashier_association = [{"role_id": role_cashier.id, "permission_id": p.id} for p in all_perms if p.name in cashier_names]
    # SALESPERSON
    sales_names = ["inventario.ver", "ventas.crear"]
    sales_association = [{"role_id": role_salesperson.id, "permission_id": p.id} for p in all_perms if p.name in sales_names]

    all_associations = owner_association + manager_association + cashier_association + sales_association
    if all_associations:
        await db.execute(role_permissions.insert(), all_associations)

    # 6. Crear el Usuario Administrador (Propietario)
    hashed_pwd = get_password_hash(payload.admin_user.password)
    admin_user = User(
        tenant_id=new_tenant.id,
        username=payload.admin_user.username,
        email=payload.admin_user.email,
        password_hash=hashed_pwd,
        role_id=role_owner.id,
        is_active=True
    )
    db.add(admin_user)
    await db.commit()
    await db.refresh(admin_user)

    # 7. Generar Tokens
    access_token = create_access_token(subject=admin_user.id)
    refresh_token = create_refresh_token(subject=admin_user.id)

    return LoginResponse(
        user=UserResponse.model_validate(admin_user),
        tenant=TenantResponse.model_validate(new_tenant),
        tokens=Token(access_token=access_token, refresh_token=refresh_token)
    )


@router.post("/login", response_model=LoginResponse)
async def login(payload: UserLogin, db: AsyncSession = Depends(get_db)):
    """
    Inicia sesión de un usuario validando credenciales y contexto de Tenant.
    Si no se envía tenant_id, se busca el usuario por email o username a nivel global.
    """
    user_identifier = payload.username_or_email or payload.email
    if not user_identifier:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Se requiere el nombre de usuario o correo electrónico para iniciar sesión."
        )

    target_tenant_id = None
    if payload.tenant_id:
        try:
            target_tenant_id = UUID(str(payload.tenant_id))
        except (ValueError, AttributeError):
            pass

        if not target_tenant_id:
            tenant_res = await db.execute(select(Tenant).where(Tenant.code == str(payload.tenant_id)))
            found_tenant = tenant_res.scalars().first()
            if found_tenant:
                target_tenant_id = found_tenant.id
            else:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"No se encontró ningún comercio con el código '{payload.tenant_id}'."
                )

        # Configurar el contexto del tenant en la sesión de la base de datos
        await db.execute(
            text("SELECT set_config('app.current_tenant', :tenant_id, false)"),
            {"tenant_id": str(target_tenant_id)}
        )

        query = select(User).where(
            (User.email == user_identifier) | (User.username == user_identifier)
        )
        result = await db.execute(query)
        user = result.scalars().first()
    else:
        # Búsqueda global si no se proveyó tenant_id específico
        await db.execute(text("SELECT set_config('app.current_tenant', '', false)"))
        query = select(User).where(
            (User.email == user_identifier) | (User.username == user_identifier)
        )
        result = await db.execute(query)
        user = result.scalars().first()
        if user:
            target_tenant_id = user.tenant_id
            await db.execute(
                text("SELECT set_config('app.current_tenant', :tenant_id, false)"),
                {"tenant_id": str(target_tenant_id)}
            )

    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Nombre de usuario, correo electrónico o contraseña incorrectos."
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El usuario se encuentra inactivo."
        )

    # Consultar Tenant asociado
    tenant_query = select(Tenant).where(Tenant.id == user.tenant_id)
    tenant_result = await db.execute(tenant_query)
    tenant = tenant_result.scalars().first()

    # Generar Tokens
    access_token = create_access_token(subject=user.id)
    refresh_token = create_refresh_token(subject=user.id)

    return LoginResponse(
        user=UserResponse.model_validate(user),
        tenant=TenantResponse.model_validate(tenant),
        tokens=Token(access_token=access_token, refresh_token=refresh_token)
    )


# --- Schema para el endpoint /refresh ---
class RefreshRequest(BaseModel):
    """C-03: Recibe el refresh token en el cuerpo (no en query param) para evitar
    que quede expuesto en logs de servidor, historial del navegador y cabeceras Referer."""
    refresh_token: str


@router.post("/refresh", response_model=Token)
async def refresh(payload_req: RefreshRequest, db: AsyncSession = Depends(get_db)):
    """
    Genera un nuevo par de tokens usando el refresh token válido.
    El refresh token se envía en el cuerpo JSON, nunca como query param.
    """
    refresh_token = payload_req.refresh_token
    try:
        payload = jwt.decode(refresh_token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        # Verificar que sea un token de tipo 'refresh', no de acceso
        if payload.get("type") != "refresh":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token de refresco inválido."
            )
        user_id = payload.get("sub")
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token de refresco inválido o vencido."
        )

    # Bypass RLS para buscar el usuario por su ID global
    await db.execute(text("SELECT set_config('app.current_tenant', '', false)"))
    query = select(User).where(User.id == UUID(user_id))
    result = await db.execute(query)
    user = result.scalars().first()

    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario no encontrado o inactivo."
        )

    # Emitir nuevos tokens (rotación de refresh token)
    new_access_token = create_access_token(subject=user.id)
    new_refresh_token = create_refresh_token(subject=user.id)

    return Token(access_token=new_access_token, refresh_token=new_refresh_token)
