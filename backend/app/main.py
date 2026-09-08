# Importación de FastAPI y generador de dependencias
from fastapi import FastAPI, Depends
# Importación del middleware de CORS
from fastapi.middleware.cors import CORSMiddleware
# Importación de constructs de consulta para verificación de salud
from sqlalchemy import text
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de la configuración centralizada
from app.core.config.settings import settings
# Importación del generador de sesiones de base de datos
from app.core.database.session import get_db
# Importación de los manejadores de excepciones globales
from app.core.exceptions.handlers import register_exception_handlers
# Importación del middleware de control de morosidad y suscripción SaaS
from app.core.middleware.subscription import SubscriptionLockMiddleware
# Importación de los routers de los módulos del sistema
from app.modules.auth_tenancy.api.endpoints import router as auth_router
from app.modules.inventory.api.endpoints import router as inventory_router

# Instanciación principal de la aplicación FastAPI
app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    docs_url=f"{settings.API_V1_STR}/docs",
    redoc_url=f"{settings.API_V1_STR}/redoc",
)

# 1. Registro de manejadores globales de excepciones (Error Envelopes estandarizados)
register_exception_handlers(app)

# 2. Registro del middleware de control de morosidad y suscripciones (Soft / Hard Lock)
app.add_middleware(SubscriptionLockMiddleware)

# 3. Configuración del middleware de CORS para conexiones seguras desde clientes frontend
if settings.BACKEND_CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[str(origin) for origin in settings.BACKEND_CORS_ORIGINS],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

# 4. Inclusión de los routers de la API versión 1
app.include_router(auth_router, prefix=settings.API_V1_STR)
app.include_router(inventory_router, prefix=settings.API_V1_STR)


# =============================================================================
# ENDPOINT DE SALUD Y MONITOREO (/health)
# =============================================================================

@app.get("/health", tags=["Health"])
async def health_check(db: AsyncSession = Depends(get_db)):
    """
    Endpoint de monitoreo y verificación de salud de la API.
    Ejecuta un ping asíncrono a PostgreSQL para validar conectividad.
    """
    try:
        # Consulta de comprobación elemental
        result = await db.execute(text("SELECT 1"))
        db_status = "connected" if result.scalar() == 1 else "unhealthy"
    except Exception as e:
        db_status = f"error: {str(e)}"

    return {
        "status": "online",
        "service": settings.PROJECT_NAME,
        "environment": settings.ENVIRONMENT,
        "database": db_status,
    }
