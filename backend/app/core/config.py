from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # App
    app_name: str = "AgentCompanion API"
    debug: bool = False

    # Database
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/agentcompanion"

    # Redis
    redis_url: str = "redis://localhost:6379/0"

    # Auth / JWT
    secret_key: str = "CHANGE-ME-in-production"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 30

    # Encryption (envelope encryption)
    encryption_key: str = "CHANGE-ME-32-byte-base64-encoded-key"

    # APNs (placeholder for push)
    apns_key_id: str = ""
    apns_team_id: str = ""
    apns_bundle_id: str = ""
    apns_key_path: str = ""

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
