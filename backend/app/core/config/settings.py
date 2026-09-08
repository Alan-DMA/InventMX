from typing import List, Union
from pydantic import AnyHttpUrl, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    PROJECT_NAME: str = "InventMX API"
    API_V1_STR: str = "/api/v1"
    ENVIRONMENT: str = "development"

    # Database
    DATABASE_URL: str = "postgresql+asyncpg://nexus_app:Admin@localhost:5432/nexus"

    # Security
    SECRET_KEY: str = "e6f0b4dca83f4f13b63ee9f3a971239c894595e1eb29976371c6183e8fa2981b"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

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
