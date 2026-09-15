from typing import AsyncGenerator
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from sqlalchemy.pool import NullPool
from app.core.config import settings

# C-04: Solo mostrar logs SQL en entorno de desarrollo
_echo_sql = settings.ENVIRONMENT == "development"

# C-06: NullPool en desarrollo/tests, pool real en producción
# NullPool: abre/cierra conexión TCP por cada request (lento pero simple en dev)
# pool_size + max_overflow: mantiene conexiones persistentes reutilizables en prod
if settings.ENVIRONMENT == "production":
    # Pool real para producción: conexiones persistentes, reutilizables
    engine = create_async_engine(
        settings.DATABASE_URL,
        echo=_echo_sql,
        pool_size=10,            # Conexiones siempre activas
        max_overflow=20,         # Conexiones extra bajo carga pico
        pool_pre_ping=True,      # Verifica conexión antes de usarla (evita stale connections)
        pool_recycle=3600,       # Recicla conexiones cada hora
    )
else:
    # NullPool para desarrollo y tests: simple, sin estado entre requests
    engine = create_async_engine(
        settings.DATABASE_URL,
        echo=_echo_sql,
        poolclass=NullPool,
    )

# Creador de sesiones asíncronas
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

Base = declarative_base()

# Dependencia para inyección de base de datos en endpoints FastAPI.
# M-01: get_db no establece tenant — eso es responsabilidad exclusiva de
# get_current_user (deps.py) y de los endpoints que manejan autenticación propia.
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Provee una sesión de base de datos asíncrona para cada request FastAPI."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()


