import os
from typing import Annotated, List, Union
from pydantic import AnyHttpUrl, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    PROJECT_NAME: str = "Nexus MX API"
    API_V1_STR: str = "/api/v1"
    ENVIRONMENT: str = "development"

    # Static uploads storage
    UPLOAD_DIR: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "uploads"))

    # Dónde se guardan las fotos de productos (`app/core/storage.py`).
    # "local" = disco del servidor bajo UPLOAD_DIR (desarrollo). "supabase" =
    # bucket público de Supabase Storage (despliegue de prueba): el disco de
    # Render se borra en cada deploy, y así las fotos las sirve el CDN de
    # Supabase y no el API. Otro proveedor = otra rama en `storage.py`.
    STORAGE_BACKEND: str = "local"
    SUPABASE_URL: str = ""
    # Llave secreta del proyecto (service_role o sb_secret_...). Sólo vive en
    # el servidor: la app nunca la recibe.
    SUPABASE_SERVICE_KEY: str = ""
    SUPABASE_STORAGE_BUCKET: str = "product-images"

    # Database
    DATABASE_URL: str = "postgresql+asyncpg://nexus_app:Admin@localhost:5432/nexus"
    # Pool de conexiones por proceso. El pooler gratuito de Supabase en modo
    # sesión admite ~15 clientes: en producción se baja por variable de entorno.
    DB_POOL_SIZE: int = 10
    DB_MAX_OVERFLOW: int = 20

    # Security
    SECRET_KEY: str = "e6f0b4dca83f4f13b63ee9f3a971239c894595e1eb29976371c6183e8fa2981b"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # Webhooks de pago SaaS: secreto compartido con cada pasarela para la firma
    # HMAC-SHA256 del cuerpo (header `X-Nexus-Signature`). Vacío = el webhook
    # rechaza todo (falla cerrado) hasta que se configure en `.env`.
    SPEI_WEBHOOK_SECRET: str = ""
    OXXO_WEBHOOK_SECRET: str = ""

    # Panel de plataforma (Fase 1). Llave de firma propia: un token de comercio
    # nunca abre el panel, ni uno del panel la app del tendero. En producción
    # ambas se fijan en `.env`; los valores de aquí son sólo de desarrollo.
    PLATFORM_JWT_SECRET: str = "dev-platform-3f1c9a7e5b2d4c6a8e0f1a3b5c7d9e2f4a6b8c0d1e3f5a7b9c2d4e6f8a0b1c3d"
    # Cifra el secreto TOTP guardado en la base (cualquier texto; se deriva la llave)
    PLATFORM_TOTP_KEY: str = "dev-totp-key-cambiar-en-produccion"
    PLATFORM_TOKEN_EXPIRE_MINUTES: int = 120
    PLATFORM_CHALLENGE_EXPIRE_MINUTES: int = 5
    PLATFORM_MAX_FAILED_ATTEMPTS: int = 5
    PLATFORM_LOCKOUT_MINUTES: int = 15

    # Ciclo de suscripción prepago (P9–P13). APAGADO hasta integrar Google Play:
    # encendido hoy bloquearía a todos al mes sin que tengan cómo renovar.
    SUBSCRIPTION_ENFORCEMENT_ENABLED: bool = False
    SUBSCRIPTION_GRACE_DAYS: int = 10
    SUBSCRIPTION_CYCLE_INTERVAL_SECONDS: int = 3600
    # Canal de renovación que la app ofrece al tendero: "NONE" hoy;
    # "GOOGLE_PLAY" el día de la integración (muestra el botón de compra).
    SUBSCRIPTION_RENEWAL_CHANNEL: str = "NONE"

    # Correo saliente (Centro de soporte, P20). "console" sólo escribe en el log
    # y guarda en memoria (desarrollo y tests); en producción se niega a
    # enviar. "brevo" usa su API transaccional (capa gratuita: 300 correos al
    # día, remitente verificado sin necesidad de dominio propio).
    EMAIL_BACKEND: str = "console"
    BREVO_API_KEY: str = ""
    EMAIL_FROM_ADDRESS: str = "soporte@nexus.mx"
    EMAIL_FROM_NAME: str = "Soporte Nexus"
    # Tope del adjunto de exportación (MB, ya comprimido)
    EMAIL_MAX_ATTACHMENT_MB: int = 10

    # Códigos de acceso de un solo uso que sustituyen a la contraseña (P16)
    LOGIN_CODE_SELF_MINUTES: int = 30
    LOGIN_CODE_ASSISTED_HOURS: int = 24
    LOGIN_CODE_MAX_ATTEMPTS: int = 5
    LOGIN_CODE_MAX_REQUESTS_PER_HOUR: int = 3

    # Eliminación de un comercio: la segunda aprobación vence si nadie la da
    TENANT_DELETION_APPROVAL_HOURS: int = 72

    # CORS en producción (`main.py`): orígenes web permitidos — vitrina, panel —
    # separados por coma. La app Android no los necesita: CORS sólo aplica a
    # navegadores. En desarrollo se acepta cualquier origen.
    ALLOWED_ORIGINS: Annotated[List[str], NoDecode] = []

    @field_validator("ALLOWED_ORIGINS", mode="before")
    @classmethod
    def _split_allowed_origins(cls, value):
        if isinstance(value, str):
            return [origin.strip().rstrip("/") for origin in value.split(",") if origin.strip()]
        return value

    # CORS
    BACKEND_CORS_ORIGINS: List[Union[str, AnyHttpUrl]] = [
        "http://localhost:3000",
        "http://localhost:8080",
        "http://localhost:5173",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8080",
        "http://127.0.0.1:5173",
    ]

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )


settings = Settings()
