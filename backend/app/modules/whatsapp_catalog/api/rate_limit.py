# Importación de colecciones para la ventana deslizante
from collections import deque
# Importación de tiempo monotónico
import time
# Importación de tipado estático
from typing import Deque, Dict, Tuple

# Importación de FastAPI
from fastapi import HTTPException, Request, status


class SlidingWindowLimiter:
    """
    Límite de peticiones por (IP, tienda) en memoria — protege el registro público
    de pedidos (sin autenticación) contra bromas y scripts. Ventana deslizante:
    `max_requests` en `window_seconds`. Un solo proceso; para producción con varios
    workers se reemplaza por Redis (misma firma).
    """

    def __init__(self, max_requests: int = 10, window_seconds: int = 60) -> None:
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._hits: Dict[Tuple[str, str], Deque[float]] = {}

    def check(self, key: Tuple[str, str]) -> None:
        """Registra el intento y lanza 429 si la ventana ya está llena."""
        now = time.monotonic()
        hits = self._hits.setdefault(key, deque())
        while hits and now - hits[0] > self.window_seconds:
            hits.popleft()
        if len(hits) >= self.max_requests:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Demasiados pedidos en poco tiempo. Espera un momento e inténtalo de nuevo.",
            )
        hits.append(now)

    def reset(self) -> None:
        """Limpia el estado (tests)."""
        self._hits.clear()


# Instancia única del proceso para el registro público de pedidos
public_order_limiter = SlidingWindowLimiter(max_requests=10, window_seconds=60)

# Lectura del ticket público: la página se refresca sola (10-30 s); 60/min
# por IP cubre a un cliente con varias pestañas y frena la lectura masiva.
public_ticket_limiter = SlidingWindowLimiter(max_requests=60, window_seconds=60)


async def limit_public_ticket(request: Request, store_slug: str) -> None:
    """Dependencia de FastAPI para `GET /public/catalog/{slug}/orders/{folio}`."""
    client_ip = request.client.host if request.client else "unknown"
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        client_ip = forwarded.split(",")[0].strip()
    public_ticket_limiter.check((client_ip, f"ticket:{store_slug.lower()}"))


async def limit_public_orders(request: Request, store_slug: str) -> None:
    """Dependencia de FastAPI: IP del cliente + slug de la tienda."""
    client_ip = request.client.host if request.client else "unknown"
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        client_ip = forwarded.split(",")[0].strip()
    public_order_limiter.check((client_ip, store_slug.lower()))
