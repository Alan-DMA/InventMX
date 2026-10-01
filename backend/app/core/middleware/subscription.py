# Importación de módulos para manejo de respuestas HTTP asíncronas en Starlette / FastAPI
import json
from typing import Callable
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

# Importación de utilidades de decodificación de tokens
from app.core.security.jwt import decode_token


async def _current_tenant_lock(tenant_id, fallback: str) -> tuple:
    """
    Estado real del comercio y motivo del bloqueo (`tenants` no tiene RLS).
    Ante cualquier duda, el estado del token y sin motivo.
    """
    import uuid as _uuid

    from sqlalchemy import select

    from app.core.database.session import AsyncSessionLocal
    from app.modules.auth_tenancy.domain.tenant import Tenant

    try:
        tenant_uuid = _uuid.UUID(str(tenant_id))
    except (TypeError, ValueError):
        return fallback, None
    try:
        async with AsyncSessionLocal() as session:
            row = (await session.execute(
                select(Tenant.status, Tenant.lock_reason).where(Tenant.id == tenant_uuid)
            )).first()
    except Exception:
        return fallback, None
    if row is None:
        return fallback, None
    return row[0].value, row[1]


# Rutas exentas de validación de bloqueo de suscripción (Auth, Webhooks, Documentación y Salud)
EXEMPT_PATHS = [
    "/health",
    "/docs",
    "/openapi.json",
    "/redoc",
    "/api/v1/auth/login",
    "/api/v1/auth/register",
    "/api/v1/auth/refresh",
    # Recuperar el acceso (P16): también desde un comercio bloqueado
    "/api/v1/auth/password-recovery",
    "/api/v1/auth/set-password",
    "/api/v1/saas/plans",
    "/api/v1/billing",
    # Un comercio bloqueado entra para ver su suscripción y renovar (P13)
    "/api/v1/auth/me",
    "/api/v1/subscription",
    # Soporte (P23): una tienda suspendida tiene que poder escribir
    "/api/v1/support/",
    # La pestaña de soporte termina o extiende su sesión aunque la tienda esté bloqueada
    "/api/v1/support-session",
    "/api/v1/webhooks",
    "/api/v1/saas-billing/webhooks",
    "/api/v1/saas-billing/plans",
]


class SubscriptionLockMiddleware(BaseHTTPMiddleware):
    """
    Middleware global de control de morosidad y máquina de estados de suscripción SaaS.
    Regla Constitucional: Artículo VI, Sección 6.3.
    
    1. SOFT_LOCK (Días 1-10 de morosidad):
       - Permite peticiones GET y HEAD (modo solo lectura para consulta de stock y reportes).
       - Bloquea peticiones de escritura (POST, PUT, PATCH, DELETE) con HTTP 403 Forbidden.
       
    2. HARD_LOCK (Día 11+ de morosidad):
       - Bloquea todas las peticiones a rutas operativas con HTTP 402 Payment Required.
       - Permite únicamente rutas de autenticación y pasarelas de pago de suscripción.
    """

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Obtener la ruta relativa de la petición actual
        path = request.url.path

        # 1. Comprobar si la ruta actual está exenta de validación de morosidad
        for exempt in EXEMPT_PATHS:
            if path.startswith(exempt):
                return await call_next(request)

        # 2. Extraer el encabezado de autorización Bearer
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            # Si no hay token, delegar a las dependencias de FastAPI para que emitan 401
            return await call_next(request)

        # 3. Extraer y decodificar el token de forma no bloqueante
        token = auth_header.split(" ")[1]
        try:
            payload = decode_token(token)
        except Exception:
            # Si el token es inválido, dejar que el endpoint o dependencia lo maneje
            return await call_next(request)

        # 4. Obtener el estado del tenant almacenado o verificar en base de datos
        tenant_status = payload.get("tenant_status", "ACTIVE")
        lock_reason = None
        # Si el token dice "bloqueado", se confirma en la base: al reactivar un
        # comercio desde el panel (pago confirmado, cortesía, cambio de estado)
        # debe poder operar de inmediato, sin esperar a renovar su token. Sólo
        # los comercios bloqueados pagan esta consulta (Panel de plataforma, CA-P7).
        if tenant_status in ("SOFT_LOCK", "HARD_LOCK"):
            tenant_status, lock_reason = await _current_tenant_lock(payload.get("tenant_id"), tenant_status)

        # 5. Aplicar reglas de bloqueo por morosidad
        if tenant_status == "HARD_LOCK":
            # Bloqueo total: HTTP 402. Una suspensión de soporte (P17) no se
            # arregla pagando: el mensaje y `details.lock_reason` lo distinguen.
            if lock_reason == "ABUSE":
                message = (
                    "Soporte Nexus suspendió tu cuenta. En Mi suscripción está el motivo "
                    "y cómo contactarnos."
                )
            else:
                message = (
                    "Tu cuenta se encuentra suspendida por falta de pago. "
                    "Renueva tu suscripción para volver a operar."
                )
            return JSONResponse(
                status_code=402,
                content={
                    "success": False,
                    "error": {
                        "code": "TENANT_HARD_LOCK",
                        "message": message,
                        "details": {"lock_reason": lock_reason or "NONPAYMENT"},
                    },
                },
            )

        if tenant_status == "SOFT_LOCK" and request.method in ["POST", "PUT", "PATCH", "DELETE"]:
            # Bloqueo de escritura: HTTP 403 Forbidden
            return JSONResponse(
                status_code=403,
                content={
                    "success": False,
                    "error": {
                        "code": "TENANT_SOFT_LOCK",
                        "message": (
                            "Comercio en periodo de gracia (Modo Solo Lectura). "
                            "No es posible crear o modificar registros hasta regularizar el pago."
                        ),
                        "details": None,
                    },
                },
            )

        # Si el comercio está activo o la petición cumple las restricciones, continuar el flujo
        return await call_next(request)
