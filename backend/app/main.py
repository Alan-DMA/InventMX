import asyncio
import logging
import os
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config.settings import settings
from app.core.database.session import get_db
from app.core.exceptions.handlers import register_exception_handlers
from app.core.middleware.subscription import SubscriptionLockMiddleware
from app.core.tasks import release_expired_reservations_loop
from app.modules.analytics_reports.api.endpoints import router as analytics_router
from app.modules.auth_tenancy.api.endpoints import router as auth_router
from app.modules.cash_treasury.api.endpoints import router as cash_treasury_router
from app.modules.community_catalog.api.endpoints import router as community_b2b_router
from app.modules.core_admin.api.endpoints import router as admin_router
from app.modules.customers_credit.api.endpoints import router as customers_router
from app.modules.inventory.api.endpoints import router as inventory_router
from app.modules.purchasing_suppliers.api.endpoints import router as purchasing_router
from app.modules.saas_billing.api.endpoints import router as saas_billing_router
from app.modules.sales_pos.api.endpoints import router as sales_router
from app.modules.whatsapp_catalog.api.endpoints import router as whatsapp_catalog_router

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Gestiona el ciclo de vida de la aplicación: inicio y apagado ordenado."""
    cleanup_task = asyncio.create_task(release_expired_reservations_loop())
    logger.info("Servicio de limpieza de stock reservado iniciado.")
    yield
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

# 1. Registrar manejadores de excepciones globales
register_exception_handlers(app)

# 2. Registrar middleware de suscripciones SaaS (bloqueo por morosidad)
app.add_middleware(SubscriptionLockMiddleware)

# 3. CORS con orígenes controlados y soporte PNA
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
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    allow_private_network=True,
)

# 4. Servir archivos estáticos subidos
os.makedirs(os.path.join(settings.UPLOAD_DIR, "images"), exist_ok=True)
app.mount("/uploads", StaticFiles(directory=settings.UPLOAD_DIR), name="uploads")

# 5. Inclusión de los routers de la API versión 1
app.include_router(auth_router, prefix=settings.API_V1_STR)
app.include_router(customers_router, prefix=settings.API_V1_STR)
app.include_router(inventory_router, prefix=settings.API_V1_STR)
app.include_router(purchasing_router, prefix=settings.API_V1_STR)
app.include_router(sales_router, prefix=settings.API_V1_STR)
app.include_router(cash_treasury_router, prefix=settings.API_V1_STR)
app.include_router(saas_billing_router, prefix=settings.API_V1_STR)
app.include_router(whatsapp_catalog_router, prefix=settings.API_V1_STR)
app.include_router(community_b2b_router, prefix=settings.API_V1_STR)
app.include_router(analytics_router, prefix=settings.API_V1_STR)
app.include_router(admin_router, prefix=settings.API_V1_STR)


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


@app.get("/health", tags=["health"])
async def health_check(db: AsyncSession = Depends(get_db)):
    """Health-check para monitorización de servicio y conexión a base de datos."""
    try:
        await db.execute(text("SELECT 1"))
        db_status = "connected"
    except Exception:
        db_status = "disconnected"

    return {
        "status": "online",
        "service": settings.PROJECT_NAME,
        "database": db_status,
        "environment": settings.ENVIRONMENT,
    }


# -----------------------------------------------------------------------------
# 6. Vitrina web (Flutter Web) servida por el propio backend — sólo desarrollo
# -----------------------------------------------------------------------------
# La vitrina pública es la app Flutter compilada a web (`frontend/build/web`).
# En producción la entrega un servidor de estáticos (nginx/CDN con `try_files`);
# para QA en LAN se sirve desde aquí y así hay un solo proceso en el :8000 y el
# enlace del chat es `http://<host>:8000/tienda/<slug>/pedido/<folio>` (sin `#`,
# que WhatsApp no linkifica). Cualquier ruta que no sea API ni archivo devuelve
# index.html (routing del lado del cliente).
_WEB_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "frontend", "build", "web")
)
if settings.ENVIRONMENT != "production" and os.path.isfile(os.path.join(_WEB_DIR, "index.html")):
    from fastapi.responses import FileResponse

    @app.get("/{web_path:path}", include_in_schema=False)
    async def serve_flutter_web(web_path: str):
        """Archivo estático si existe; si no, la app (SPA fallback)."""
        if web_path.startswith(("api/", "uploads/", "docs", "redoc", "openapi.json")):
            from fastapi import HTTPException
            raise HTTPException(status_code=404)
        candidate = os.path.normpath(os.path.join(_WEB_DIR, web_path))
        if candidate.startswith(_WEB_DIR) and os.path.isfile(candidate):
            return FileResponse(candidate)
        return FileResponse(os.path.join(_WEB_DIR, "index.html"))
