# Importación de asyncio para colas por suscriptor
import asyncio
# Importación de tipado estático
from typing import Any, Dict, Set
# Importación de identificadores UUID
import uuid


class OrderEventHub:
    """
    Pub/sub en memoria de eventos de pedidos web, por comercio (tenant).

    Cada conexión WebSocket abierta desde la app del tendero se suscribe con una
    cola propia; `submit_order`/cambios de estado publican al tenant y todas las
    colas reciben el evento. Vive en el proceso: con un solo worker de uvicorn
    basta. Para varios workers en producción hay que reemplazar el fan-out por
    Redis pub/sub — el resto del contrato (evento JSON) no cambia.

    Los eventos son la notificación, nunca la fuente de verdad: el badge y la
    lista siempre se piden al servidor (`GET /catalog-orders`), así que si una
    cola se llena o el socket se cae, el tendero pierde inmediatez, no pedidos.
    """

    # Tamaño máximo de la cola de un suscriptor antes de descartar (cliente colgado)
    _MAX_QUEUE = 100

    def __init__(self) -> None:
        self._subscribers: Dict[uuid.UUID, Set["asyncio.Queue[Dict[str, Any]]"]] = {}

    def subscribe(self, tenant_id: uuid.UUID) -> "asyncio.Queue[Dict[str, Any]]":
        """Registra una conexión y devuelve su cola de eventos."""
        queue: "asyncio.Queue[Dict[str, Any]]" = asyncio.Queue(maxsize=self._MAX_QUEUE)
        self._subscribers.setdefault(tenant_id, set()).add(queue)
        return queue

    def unsubscribe(self, tenant_id: uuid.UUID, queue: "asyncio.Queue[Dict[str, Any]]") -> None:
        """Retira la conexión; limpia el tenant si ya no tiene suscriptores."""
        subs = self._subscribers.get(tenant_id)
        if not subs:
            return
        subs.discard(queue)
        if not subs:
            self._subscribers.pop(tenant_id, None)

    def publish(self, tenant_id: uuid.UUID, event: Dict[str, Any]) -> int:
        """
        Entrega el evento a todas las conexiones del tenant. Nunca bloquea: si una
        cola está llena se descarta para ese suscriptor (se recuperará con `since`).
        Devuelve cuántas conexiones lo recibieron.
        """
        delivered = 0
        for queue in list(self._subscribers.get(tenant_id, ())):
            try:
                queue.put_nowait(event)
                delivered += 1
            except asyncio.QueueFull:
                continue
        return delivered

    def connections(self, tenant_id: uuid.UUID) -> int:
        """Conexiones abiertas del comercio (para pruebas y diagnóstico)."""
        return len(self._subscribers.get(tenant_id, ()))


# Instancia única del proceso
order_event_hub = OrderEventHub()
