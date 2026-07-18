from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # Database
    database_url: str  # postgresql+asyncpg://user:pass@host/db
    is_celery_worker:bool = False  # True if running as a Celery worker, False for FastAPI app

    # Auth
    secret_key: str
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7  # 7 days

    # GCS
    gcs_bucket_name: str
    google_application_credentials: str = ""  # path to service account JSON

    # Redis (Upstash)
    redis_url: str  # rediss://default:token@host:port

    # Audio processing
    segment_length_sec: float = 3.0
    silence_threshold_dbfs: float = -60.0
    sample_rate: int = 22050

    # Active learning
    rejection_threshold: int = 150

    # Cloud Run Job (retraining)
    gcp_project_id: str
    gcp_region: str = "us-central1"
    retrain_job_name: str = "forest-sound-retrain"

    # Model
    model_gcs_prefix: str = "models/"

    class Config:
        env_file = ".env"


@lru_cache
def get_settings() -> Settings:
    return Settings()
