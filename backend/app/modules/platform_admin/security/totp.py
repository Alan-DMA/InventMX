"""
TOTP (RFC 6238) para Google Authenticator, sin dependencias externas.

Constitución Art. IV: el algoritmo son unas líneas de HMAC-SHA1 sobre el paso
de 30 s; no justifica una librería. Parámetros fijos de Google Authenticator:
6 dígitos, SHA-1, 30 segundos.
"""
# Importación de primitivas de la biblioteca estándar
import base64
import hashlib
import hmac
import secrets
import struct
import time
# Importación de tipado estático
from typing import Optional
from urllib.parse import quote

# Parámetros que Google Authenticator espera por defecto
DIGITS = 6
PERIOD_SECONDS = 30
# Tolerancia de reloj: el paso anterior y el siguiente (±30 s)
WINDOW = 1
# Nombre del emisor que aparece en la app autenticadora
ISSUER = "Nexus Plataforma"


def generate_secret() -> str:
    """Secreto aleatorio de 160 bits en Base32 (lo que se escanea en el QR)."""
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii").rstrip("=")


def provisioning_uri(secret: str, account_email: str) -> str:
    """URI `otpauth://` que codifica el QR de vinculación."""
    label = quote(f"{ISSUER}:{account_email}")
    return (
        f"otpauth://totp/{label}?secret={secret}&issuer={quote(ISSUER)}"
        f"&algorithm=SHA1&digits={DIGITS}&period={PERIOD_SECONDS}"
    )


def current_step(now: Optional[float] = None) -> int:
    """Número de paso de 30 s desde la época Unix."""
    return int((time.time() if now is None else now) // PERIOD_SECONDS)


def code_at(secret: str, step: int) -> str:
    """Código de 6 dígitos para un paso (RFC 4226, truncado dinámico)."""
    padded = secret.upper() + "=" * (-len(secret) % 8)
    key = base64.b32decode(padded)
    digest = hmac.new(key, struct.pack(">Q", step), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
    return str(value % (10 ** DIGITS)).zfill(DIGITS)


def verify(
    secret: str,
    code: str,
    last_used_step: Optional[int],
    now: Optional[float] = None,
) -> Optional[int]:
    """
    Devuelve el paso que coincide, o None.

    Un código ya usado (paso ≤ `last_used_step`) se rechaza aunque siga siendo
    válido en la ventana: quien lo vea por encima del hombro no puede repetirlo.
    """
    cleaned = (code or "").replace(" ", "").strip()
    if len(cleaned) != DIGITS or not cleaned.isdigit():
        return None
    step_now = current_step(now)
    for step in range(step_now - WINDOW, step_now + WINDOW + 1):
        if last_used_step is not None and step <= last_used_step:
            continue
        if hmac.compare_digest(code_at(secret, step), cleaned):
            return step
    return None
