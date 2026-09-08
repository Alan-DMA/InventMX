# Importación de módulos para manejo de respuestas HTTP asíncronas en Starlette / FastAPI
import json
from typing import Callable
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

# Importación de utilidades de decodificación de tokens
from app.core.security.jwt import decode_token

# Rutas exentas de validación de bloqueo de suscripción (Auth, Webhooks, Documentación y Salud)
EXEMPT_PATHS = [
    "/health",
    "/docs",
    "/openapi.json",
    "/redoc",
    "/api/v1/auth/login",
    "/api/v1/auth/register",
    "/api/v1/auth/refresh",
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

        # 5. Aplicar reglas de bloqueo por morosidad
        if tenant_status == "HARD_LOCK":
            # Bloqueo total: HTTP 402 Payment Required
            return JSONResponse(
                status_code=402,
                content={
                    "success": False,
                    "error": {
                        "code": "TENANT_HARD_LOCK",
                        "message": (
                            "Tu cuenta se encuentra suspendida por falta de pago. "
                            "Por favor accede al módulo de facturación para regularizar tu suscripción."
                        ),
                        "details": None,
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
