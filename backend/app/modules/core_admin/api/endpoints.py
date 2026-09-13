# Endpoints REST para el módulo de administración, respaldos y monitoreo (Día 16 / HU-25 / CU-31)
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import get_db
from app.core.security.deps import get_current_user
from app.modules.auth_tenancy.domain.user import User
from app.modules.core_admin.schemas.backup_schemas import (
    BackupCreateRequest,
    BackupListResponse,
    BackupMetadataResponse,
    SystemHealthCheckResponse,
)
from app.modules.core_admin.services.backup_service import BackupService

# Inicialización del router de administración central
router = APIRouter(prefix="/admin", tags=["Admin & Backups"])


def get_backup_service(db: AsyncSession = Depends(get_db)) -> BackupService:
    """Inyección de dependencias para el servicio de administración y respaldos."""
    return BackupService(db)


@router.post(
    "/backups/create",
    response_model=BackupMetadataResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Crear respaldo comprimido y firmado de la base de datos",
)
async def create_backup(
    request: BackupCreateRequest,
    current_user: User = Depends(get_current_user),
    service: BackupService = Depends(get_backup_service),
):
    """
    Genera un respaldo de base de datos comprimido con gzip, calculando su checksum SHA-256
    y registrándolo en almacenamiento seguro compatible con Cloudflare R2 / S3.
    Requiere privilegios de Dueño (OWNER) o Administrador.
    """
    # Verificación de permisos de rol (RBAC)
    role_name = current_user.role.name if current_user.role else ""
    if role_name not in ["OWNER", "ADMIN"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado: Solo el dueño de la cuenta puede generar respaldos de base de datos.",
        )

    return await service.create_database_backup(request, current_user)


@router.get(
    "/backups/list",
    response_model=BackupListResponse,
    status_code=status.HTTP_200_OK,
    summary="Listar respaldos disponibles y estado de cuota",
)
async def list_backups(
    current_user: User = Depends(get_current_user),
    service: BackupService = Depends(get_backup_service),
):
    """
    Retorna el inventario cronológico de respaldos disponibles y el consumo de almacenamiento.
    Requiere rol de Dueño (OWNER).
    """
    role_name = current_user.role.name if current_user.role else ""
    if role_name not in ["OWNER", "ADMIN"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado: Solo el dueño de la cuenta puede consultar los respaldos.",
        )

    return await service.list_backups(current_user)


@router.get(
    "/system-health",
    response_model=SystemHealthCheckResponse,
    status_code=status.HTTP_200_OK,
    summary="Diagnóstico integral de salud operativa y seguridad RLS",
)
async def get_system_health(
    current_user: User = Depends(get_current_user),
    service: BackupService = Depends(get_backup_service),
):
    """
    Retorna el estado de conectividad a PostgreSQL, latencia en ms, estado de aislamiento RLS
    y volumen de operaciones registradas en el sistema.
    """
    return await service.get_system_health(current_user)
