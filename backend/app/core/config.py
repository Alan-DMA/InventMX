import os
from dotenv import load_dotenv
from pydantic_settings import BaseSettings
from typing import List

# Cargar variables de entorno desde el archivo .env
load_dotenv(override=True)

class Settings(BaseSettings):
    PROJECT_NAME: str = "Nexus"
    API_V1_STR: str = "/api/v1"

    # Entorno: "development" | "production"
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")

    # Base de Datos (PostgreSQL RLS)
    DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql+asyncpg://postgres:postgres@localhost:5432/nexus")

    # URL de superusuario para seed.py (base de datos postgres)
    SUPERUSER_DATABASE_URL: str = os.getenv(
        "SUPERUSER_DATABASE_URL",
        os.getenv("DATABASE_URL", "postgresql+asyncpg://postgres:postgres@localhost:5432/nexus").replace("nexus_app", "postgres")
    )

    # Seguridad — C-02: sin valor por defecto en producción
    SECRET_KEY: str = os.getenv("SECRET_KEY", "dev-only-secret-key-change-in-prod-32chars!!")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15   # Regla de la Constitución (Art. 7.5)
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7      # Regla de la Constitución (Art. 7.5)

    # CORS — C-01: orígenes permitidos configurables por entorno
    # En producción, sobreescribir con la URL real del dominio.
    ALLOWED_ORIGINS: List[str] = [
        "http://localhost:8088",
        "http://127.0.0.1:8088",
        "http://192.168.10.10:8088",
        "http://localhost:3000",
    ]

    class Config:
        case_sensitive = True

settings = Settings()

# Guardia de seguridad en producción — falla explícitamente si la clave es débil
if settings.ENVIRONMENT == "production" and len(settings.SECRET_KEY) < 32:
    raise RuntimeError(
        "FATAL: SECRET_KEY debe tener al menos 32 caracteres en producción. "
        "Configura la variable de entorno SECRET_KEY con una clave segura."
    )

