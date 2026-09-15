from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
import asyncio
import logging

from app.api.v1.auth import router as auth_router
from app.api.v1.inventory import router as inventory_router
from app.api.v1.sales import router as sales_router
from app.core.config import settings
from app.core.tasks import release_expired_reservations_loop

# Logger del módulo principal
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Gestiona el ciclo de vida de la aplicación: inicio y apagado ordenado."""
    # Startup: iniciar la tarea periódica de liberación de stock expirado (TTL 15 min)
    cleanup_task = asyncio.create_task(release_expired_reservations_loop())
    logger.info("Servicio de limpieza de stock reservado iniciado.")
    yield
    # Shutdown: cancelar la tarea limpiamente al apagar el servidor
    cleanup_task.cancel()
    try:
        await cleanup_task
    except asyncio.CancelledError:
        logger.info("Servicio de limpieza de stock reservado detenido correctamente.")


app = FastAPI(
    title="Nexus API",
    description="Gestión Comercial Modular — Sistema Nexus",
    version="1.0.0",
    lifespan=lifespan,
)

# --- C-01: CORS con orígenes controlados por configuración ---
# En producción se usan settings.ALLOWED_ORIGINS estrictos.
# En desarrollo se permiten explícitamente localhost, 127.0.0.1 y la IP local, además de regex.
_dev_origins = [
    "http://localhost:8088",
    "http://127.0.0.1:8088",
    "http://localhost:8000",
    "http://127.0.0.1:8000",
    "http://192.168.10.10:8088",
    "http://localhost:3000",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS if settings.ENVIRONMENT == "production" else _dev_origins,
    allow_origin_regex=None if settings.ENVIRONMENT == "production" else r"^https?://.*",
    allow_credentials=True,                   # Necesario para cookies / auth headers
    allow_methods=["*"],                       # GET, POST, PUT, DELETE, PATCH, OPTIONS
    allow_headers=["*"],                       # Authorization, Content-Type, etc.
    allow_private_network=True,                # Soporte nativo para Chrome Private Network Access (PNA)
)

# --- B-07: Handler global de errores 500 ---
# Evita que los stack traces del servidor se expongan en la respuesta HTTP.
@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Captura cualquier excepción no manejada y devuelve un 500 seguro."""
    logger.exception(f"Error no manejado en {request.method} {request.url}: {exc}")
    return JSONResponse(
        status_code=500,
        content={"detail": "Error interno del servidor. Por favor intente más tarde."},
    )


# --- Registrar Routers ---
app.include_router(auth_router,      prefix="/api/v1/auth",      tags=["auth"])
app.include_router(inventory_router, prefix="/api/v1/inventory",  tags=["inventory"])
app.include_router(sales_router,     prefix="/api/v1/sales",      tags=["sales"])


@app.get("/", tags=["health"])
def read_root():
    """Health-check básico del servidor."""
    return {
        "name": "Nexus API",
        "version": "1.0.0",
        "status": "active",
        "environment": settings.ENVIRONMENT,
        "message": "Bienvenido al Sistema de Gestión Comercial Nexus",
    }
