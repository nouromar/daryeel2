from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="API_", extra="ignore")

    app_env: str = "local"
    public_base_url: str = ""

    # Backing services
    database_url: str = ""  # Use DATABASE_URL env var (not prefixed) in Docker.
    redis_url: str = ""
    default_pharmacy_id: str = ""

    # Auth (dev-only OTP for now)
    auth_secret: str = "dev-insecure-secret"
    access_token_ttl_seconds: int = 60 * 60 * 24 * 30  # 30 days

    def is_dev_env(self) -> bool:
        # Treat local + docker as dev for now.
        return self.app_env.lower() in {"local", "development", "docker"}


def load_settings() -> Settings:
    # For backwards compatibility with common conventions, allow DATABASE_URL.
    # Prefer explicit API_DATABASE_URL when set.
    s = Settings()
    return s
