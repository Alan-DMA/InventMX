"""
Cifrado del secreto TOTP en reposo (Fernet, de `cryptography`, ya instalada).

Si alguien obtiene un respaldo de la base, sin `PLATFORM_TOTP_KEY` no puede
generar códigos del panel. La llave Fernet se deriva del texto configurado.
"""
# Importación de primitivas de la biblioteca estándar
import base64
import hashlib

# Importación de Fernet (cifrado autenticado)
from cryptography.fernet import Fernet

from app.core.config.settings import settings


def _fernet() -> Fernet:
    key = base64.urlsafe_b64encode(hashlib.sha256(settings.PLATFORM_TOTP_KEY.encode("utf-8")).digest())
    return Fernet(key)


def encrypt(plain: str) -> str:
    return _fernet().encrypt(plain.encode("utf-8")).decode("ascii")


def decrypt(token: str) -> str:
    return _fernet().decrypt(token.encode("ascii")).decode("utf-8")
