import os
from typing import List, Union
from pydantic import AnyHttpUrl, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    PROJECT_NAME: str = "Nexus MX API"
    API_V1_STR: str = "/api/v1"
    ENVIRONMENT: str = "development"

    # Static uploads storage
    UPLOAD_DIR: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "uploads"))

    # Database
    DATABASE_URL: str = "postgresql+asyncpg://nexus_app:Admin@localhost:5432/nexus"

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
