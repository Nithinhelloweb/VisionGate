from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field
from typing import Optional
import os


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # Database settings
    PG_HOST: str = Field(default="localhost")
    PG_PORT: int = Field(default=5432)
    PG_USER: str = Field(default="attenda")
    PG_PASSWORD: str = Field(default="attenda_password")
    PG_DB: str = Field(default="attenda")
    PG_POOL_MIN_SIZE: int = Field(default=5)
    PG_POOL_MAX_SIZE: int = Field(default=20)

    # Database alias properties for backward/migration compatibility
    @property
    def DB_HOST(self) -> str:
        return self.PG_HOST

    @property
    def DB_PORT(self) -> int:
        return self.PG_PORT

    @property
    def DB_USER(self) -> str:
        return self.PG_USER

    @property
    def DB_PASSWORD(self) -> str:
        return self.PG_PASSWORD

    @property
    def DB_NAME(self) -> str:
        return self.PG_DB

    # Redis settings
    REDIS_HOST: str = Field(default="localhost")
    REDIS_PORT: int = Field(default=6379)
    REDIS_PASSWORD: Optional[str] = Field(default=None)
    REDIS_DB: int = Field(default=0)

    # Security settings
    SECRET_KEY: str = Field(default="visiongate_default_jwt_secret_change_in_production")
    JWT_SECRET: Optional[str] = Field(default=None)
    ALGORITHM: str = Field(default="HS256")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=60)

    # App settings
    APP_ENV: str = Field(default="production")
    DEBUG: bool = Field(default=False)
    LOG_LEVEL: str = Field(default="INFO")
    WORKERS: int = Field(default=4)

    # Face recognition settings
    FACE_CONFIDENCE_THRESHOLD: float = Field(default=0.60)
    FACE_MIN_COSINE_SIMILARITY: float = Field(default=0.50)
    FACE_MAX_EUCLIDEAN_DISTANCE: float = Field(default=1.2)
    MAX_PROFILE_SAMPLES: int = Field(default=24)

    # Anti-spoofing settings
    ANTISPOOFING_ENABLED: bool = Field(default=True)
    ANTISPOOF_STRICT_MODE: bool = Field(default=False)

    # Security settings
    MAX_FAILED_ATTEMPTS: int = Field(default=20)
    LOCKOUT_DURATION_MINUTES: int = Field(default=5)

    # Geo-fence settings
    ENFORCE_GEO_FENCE: bool = Field(default=True)
    ENFORCE_VPN_BLOCKING: bool = Field(default=True)
    ENFORCE_APP_GEO_FENCE: bool = Field(default=True)

    # Rate limiting settings
    RATE_LIMIT_REQUESTS_PER_MINUTE: int = Field(default=60)
    RATE_LIMIT_BURST: int = Field(default=10)

    # Paths
    MODELS_DIR: str = Field(default_factory=lambda: os.environ.get("INSIGHTFACE_HOME", os.path.expanduser("~/.insightface")))

    @property
    def database_url(self) -> str:
        return f"postgresql://{self.PG_USER}:{self.PG_PASSWORD}@{self.PG_HOST}:{self.PG_PORT}/{self.PG_DB}"

    @property
    def redis_url(self) -> str:
        if self.REDIS_PASSWORD:
            return f"redis://:{self.REDIS_PASSWORD}@{self.REDIS_HOST}:{self.REDIS_PORT}/{self.REDIS_DB}"
        return f"redis://{self.REDIS_HOST}:{self.REDIS_PORT}/{self.REDIS_DB}"

    @property
    def is_production(self) -> bool:
        return self.APP_ENV.lower() == "production"

    @property
    def is_development(self) -> bool:
        return self.APP_ENV.lower() == "development"


settings = Settings()