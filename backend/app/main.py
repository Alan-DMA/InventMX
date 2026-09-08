from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.config.settings import settings
from app.core.database.session import get_db

app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    docs_url=f"{settings.API_V1_STR}/docs",
    redoc_url=f"{settings.API_V1_STR}/redoc",
)

# Configuración de CORS
if settings.BACKEND_CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[str(origin) for origin in settings.BACKEND_CORS_ORIGINS],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )


@app.get("/health", tags=["Health"])
async def health_check(db: AsyncSession = Depends(get_db)):
    """
    Endpoint de salud del servicio.
    Verifica la conexión asíncrona a la base de datos PostgreSQL.
    """
    try:
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
