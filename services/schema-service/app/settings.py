from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "daryeel2-runtime-service"
    app_env: str = "development"

    # Optional external/public base URL for this service (e.g. behind a proxy).
    # When set, /config/bootstrap will advertise this URL for schema/theme endpoints.
    public_base_url: str | None = None

    # Optional Redis URL for shared caching (e.g. "redis://localhost:6379/0").
    # When unset, schema-service uses in-process caching only.
    redis_url: str | None = None

    # Key prefix for Redis (and other) cache backends.
    redis_key_prefix: str = "daryeel2:schema-service:"

    model_config = SettingsConfigDict(env_prefix="SCHEMA_SERVICE_")


settings = Settings()