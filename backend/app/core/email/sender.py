"""
Correo saliente (Centro de soporte, P20).

Una sola puerta, `send_email`, con dos transportes:
- `console`: escribe asunto y destinatario en el log (en `development`, el
  correo completo en la consola del servidor, para el QA) y guarda el mensaje en
  `console_outbox` (los tests lo leen de ahí). En producción se niega a enviar:
  un código de acceso impreso en el log lo vería quien lea el servidor, y el
  operador nunca debe ver un código (P22).
- `brevo`: API transaccional de Brevo (capa gratuita, remitente verificado).

Quien llama decide qué hacer si falla (`EmailDeliveryError`): la recuperación
responde igual para no delatar correos; la exportación queda FALLIDA en el feed.
"""
import base64
import logging
import sys
from dataclasses import dataclass, field
from typing import List, Optional

import httpx

from app.core.config.settings import settings

logger = logging.getLogger(__name__)

BREVO_URL = "https://api.brevo.com/v3/smtp/email"


class EmailDeliveryError(Exception):
    """El proveedor no aceptó el correo (o no hay transporte válido)."""


@dataclass(frozen=True)
class Attachment:
    filename: str
    content: bytes


@dataclass
class EmailMessage:
    to_email: str
    subject: str
    text: str
    to_name: Optional[str] = None
    attachments: List[Attachment] = field(default_factory=list)


# Buzón en memoria del transporte `console` (desarrollo y tests)
console_outbox: List[EmailMessage] = []


async def send_email(message: EmailMessage) -> None:
    backend = settings.EMAIL_BACKEND.strip().lower()
    if backend == "brevo":
        await _send_brevo(message)
    elif backend == "console":
        if settings.ENVIRONMENT == "production":
            raise EmailDeliveryError("EMAIL_BACKEND=console no envía correos en producción.")
        console_outbox.append(message)
        logger.info("Correo (console) para %s: %s", message.to_email, message.subject)
        if settings.ENVIRONMENT == "development":
            # Para el QA en el teléfono: el código de recuperación sólo existe en el correo
            _echo(
                f"\n──── Correo (console) → {message.to_email}\nAsunto: {message.subject}\n\n{message.text}\n"
                + "".join(f"[adjunto: {a.filename}, {len(a.content)} bytes]\n" for a in message.attachments)
                + "────\n"
            )
    else:
        raise EmailDeliveryError(f"EMAIL_BACKEND desconocido: {settings.EMAIL_BACKEND!r}")


def _echo(text: str) -> None:
    """
    Imprime en la consola del servidor sin romper nunca la petición: en Windows
    la consola suele ser cp1252 y "→" o "ó" lanzaban UnicodeEncodeError (500 en
    la recuperación, hallado en el QA contra el servidor real).
    """
    encoding = getattr(sys.stdout, "encoding", None) or "utf-8"
    try:
        sys.stdout.write(text.encode(encoding, errors="replace").decode(encoding, errors="replace"))
        sys.stdout.flush()
    except Exception:  # la consola es un apoyo de QA, no parte del envío
        logger.debug("No se pudo imprimir el correo en consola.", exc_info=True)


async def _send_brevo(message: EmailMessage) -> None:
    if not settings.BREVO_API_KEY:
        raise EmailDeliveryError("Falta BREVO_API_KEY.")
    payload = {
        "sender": {"email": settings.EMAIL_FROM_ADDRESS, "name": settings.EMAIL_FROM_NAME},
        "to": [{"email": message.to_email, **({"name": message.to_name} if message.to_name else {})}],
        "subject": message.subject,
        "textContent": message.text,
    }
    if message.attachments:
        payload["attachment"] = [
            {"name": a.filename, "content": base64.b64encode(a.content).decode("ascii")}
            for a in message.attachments
        ]
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(
                BREVO_URL,
                json=payload,
                headers={"api-key": settings.BREVO_API_KEY, "accept": "application/json"},
            )
    except httpx.HTTPError as err:
        raise EmailDeliveryError(f"Sin conexión con Brevo: {err.__class__.__name__}") from err
    if response.status_code >= 300:
        # El cuerpo de Brevo explica el rechazo; nunca lleva el contenido del correo
        raise EmailDeliveryError(f"Brevo respondió {response.status_code}: {response.text[:200]}")
