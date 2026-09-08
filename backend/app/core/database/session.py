import uuid
from typing import AsyncGenerator, Union
from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from app.core.config.settings import settings

# Motor asíncrono con schema inventmx y pool de conexiones optimizado
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=(settings.ENVIRONMENT == "development"),
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,
    pool_recycle=3600,
    connect_args={
        "server_settings": {
            "search_path": "inventmx,public"
        }
    },
)

# Fábrica de sesiones asíncronas
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """
    Generador de dependencias de sesión de base de datos para FastAPI.
    Garantiza el cierre adecuado de la sesión tras completar la petición.
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()


async def set_tenant_context(
    session: AsyncSession, tenant_id: Union[uuid.UUID, str]
) -> None:
    """
    Inyecta de forma segura la variable de contexto de sesión en PostgreSQL para RLS.
    Utiliza la función nativa set_config de PostgreSQL con enlace seguro de parámetros.
    """
    if not tenant_id:
        await session.execute(text("SELECT set_config('app.current_tenant', '', false);"))
        return

    str_tenant_id = str(tenant_id)
    # Validación estricta de formato UUID para mitigar manipulación de variables
    validated_uuid = uuid.UUID(str_tenant_id)
    
    await session.execute(
        text("SELECT set_config('app.current_tenant', :tenant_id, false);"),
        {"tenant_id": str(validated_uuid)},
    )
