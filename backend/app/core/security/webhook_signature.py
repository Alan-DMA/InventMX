"""
Firma de webhooks de pago (Panel de plataforma, Fase 0 — Sep 2026).

Un webhook de pago reactiva cuentas: sin firma, cualquiera que conozca una
referencia podría marcar una factura como pagada. La pasarela firma el cuerpo
crudo con HMAC-SHA256 y un secreto compartido; aquí se recalcula y se compara
en tiempo constante. Sin secreto configurado no se acepta nada (falla cerrado).
"""
# Importación de primitivas criptográficas de la biblioteca estándar
import hashlib
import hmac
import logging
# Importación de tipado estático
from typing import Optional

# Importación de excepciones HTTP de FastAPI
from fastapi import HTTPException, status

logger = logging.getLogger(__name__)

# Header donde la pasarela manda la firma, en hexadecimal (admite prefijo `sha256=`)
SIGNATURE_HEADER = "X-Nexus-Signature"


def sign_webhook_body(body: bytes, secret: str) -> str:
    """Firma HMAC-SHA256 del cuerpo, en hexadecimal."""
    return hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()


def verify_webhook_signature(
    body: bytes, signature: Optional[str], secret: str, provider: str
) -> None:
    """
    503 si el webhook no tiene secreto configurado; 401 si la firma falta o no
    coincide. Los rechazos van al log de la aplicación y no a la base: guardar
    peticiones sin autenticar abriría la puerta a llenar la bitácora con basura.
    """
    if not secret:
        logger.error("Webhook %s rechazado: no hay secreto configurado.", provider)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Webhook no configurado.",
        )

    provided = (signature or "").strip()
    if provided.lower().startswith("sha256="):
        provided = provided[len("sha256="):]

    expected = sign_webhook_body(body, secret)
    if not provided or not hmac.compare_digest(expected, provided.lower()):
        logger.warning("Webhook %s rechazado: firma ausente o inválida.", provider)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firma de webhook inválida.",
        )
