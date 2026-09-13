# Esquemas Pydantic v2 para el módulo de administración, auditoría y respaldos (Día 16 / HU-25 / CU-31)
from datetime import datetime, timezone
from enum import Enum
from typing import List, Optional
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field


class BackupType(str, Enum):
    """Tipos de respaldo de base de datos admitidos."""
    FULL = "FULL"
    SCHEMA_ONLY = "SCHEMA_ONLY"
    DATA_ONLY = "DATA_ONLY"


class BackupStatus(str, Enum):
    """Estados del ciclo de vida de un respaldo."""
    PENDING = "PENDING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"


class StorageProvider(str, Enum):
    """Proveedores de almacenamiento en la nube compatibles con S3."""
    LOCAL = "LOCAL"
    CLOUDFLARE_R2 = "CLOUDFLARE_R2"
    BACKBLAZE_B2 = "BACKBLAZE_B2"
    AWS_S3 = "AWS_S3"


class BackupCreateRequest(BaseModel):
    """Payload para solicitar la creación de un nuevo respaldo de base de datos."""
    backup_type: BackupType = Field(default=BackupType.FULL, description="Tipo de respaldo a generar")
    include_all_tenants: bool = Field(default=True, description="Si incluye todos los esquemas o solo el tenant actual")
    notes: Optional[str] = Field(default=None, max_length=255, description="Notas explicativas del respaldo")

    model_config = ConfigDict(from_attributes=True)


class BackupMetadataResponse(BaseModel):
    """Metadatos detallados de un archivo de respaldo generado."""
    id: str = Field(description="Identificador único del respaldo")
    filename: str = Field(description="Nombre del archivo comprimido .tar.gz / .sql.gz")
    backup_type: BackupType = Field(description="Tipo de respaldo")
    status: BackupStatus = Field(description="Estado de la ejecución")
    size_bytes: int = Field(description="Tamaño exacto del archivo en bytes")
    sha256_checksum: str = Field(description="Hash criptográfico SHA-256 para verificación de integridad")
    storage_provider: StorageProvider = Field(description="Proveedor donde se encuentra alojado el respaldo")
    created_at: datetime = Field(description="Fecha y hora de generación")
    expires_at: datetime = Field(description="Fecha y hora de expiración según política de retención de 30 días")
    tables_count: int = Field(description="Número de tablas incluidas en el volcado")
    records_count: int = Field(description="Número total estimado de registros respaldados")
    notes: Optional[str] = Field(default=None, description="Notas del respaldo")

    model_config = ConfigDict(from_attributes=True)


class BackupListResponse(BaseModel):
    """Respuesta con el listado de respaldos disponibles y cuota de almacenamiento."""
    total_backups: int = Field(description="Total de respaldos vigentes")
    total_size_bytes: int = Field(description="Consumo total de almacenamiento en bytes")
    retention_policy_days: int = Field(default=30, description="Días de retención configurados")
    backups: List[BackupMetadataResponse] = Field(description="Listado cronológico de respaldos")

    model_config = ConfigDict(from_attributes=True)


class SystemHealthCheckResponse(BaseModel):
    """Diagnóstico integral de salud operativa, latencia de base de datos y estado de seguridad RLS."""
    status: str = Field(description="Estado global: healthy, degraded, unhealthy")
    database_connected: bool = Field(description="Indicador de conectividad activa a PostgreSQL")
    database_latency_ms: float = Field(description="Latencia de respuesta de la base de datos en milisegundos")
    rls_enforced: bool = Field(description="Confirmación de aislamiento Row-Level Security activo")
    version: str = Field(description="Versión del software Nexus v3")
    timestamp: datetime = Field(description="Estampa de tiempo del diagnóstico")
    environment: str = Field(description="Entorno de ejecución (development, staging, production)")
    active_tenants_count: int = Field(description="Número total de comercios activos en el SaaS")
    total_products_count: int = Field(description="Total de artículos registrados en inventario")
    total_sales_count: int = Field(description="Total de transacciones de venta procesadas")

    model_config = ConfigDict(from_attributes=True)
