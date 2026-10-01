"""
Sólo lectura para las sesiones de soporte (Centro de soporte, etapa 4, P37).

Un token con `support_session` sólo puede leer: cualquier POST/PUT/PATCH/DELETE
se rechaza aquí, antes de llegar a la ruta, sin importar qué endpoint sea (una
ruta nueva queda cubierta sin tocarla). La única excepción es la propia sesión:
extenderla y terminarla. La vigencia de la sesión la confirma `get_current_user`.
"""
from typing import Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from app.core.config.settings import settings
from app.core.security.jwt import decode_token

SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})
SESSION_PATH = f"{settings.API_V1_STR}/support-session"


class SupportReadOnlyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        if request.method in SAFE_METHODS or request.url.path.startswith(SESSION_PATH):
            return await call_next(request)
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return await call_next(request)
        try:
            payload = decode_token(auth.split(" ", 1)[1])
        except Exception:
            # Inválido o vencido: que lo rechace la dependencia de la ruta
            return await call_next(request)
        if payload.get("support_session"):
            return JSONResponse(
                status_code=403,
                content={
                    "success": False,
                    "error": {
                        "code": "SUPPORT_READ_ONLY",
                        "message": "Modo soporte: sólo lectura. No se guardó nada.",
                        "details": None,
                    },
                },
            )
        return await call_next(request)
