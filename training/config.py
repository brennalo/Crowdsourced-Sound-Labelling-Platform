from pydantic_settings import BaseSettings
from functools import lru_cache


class TrainingSettings(BaseSettings):
    # GCS
    gcs_bucket_name: str
    google_application_credentials: str = ""

    # Database (Neon) — used by retraining job to update status
    database_url: str = ""

    # Audio — must match backend config exactly
    sample_rate: int = 22050
    segment_length_sec: float = 3.0
    n_mels: int = 64
    hop_length: int = 512
    n_fft: int = 1024

    # Model
    model_gcs_prefix: str = "models/"
    num_classes: int = 2

    # Training hyperparameters
    batch_size: int = 32
    num_epochs: int = 30
    learning_rate: float = 1e-3
    val_split: float = 0.2
    early_stopping_patience: int = 5

    # Labels — order must match ONNX output index
    labels: list[str] = ["chainsaw", "environment"]

    # Retraining job ID (injected by Celery worker via env)
    retraining_job_id: str = ""

    frugalai_cap: int=5000
    frugalai_seed: int = 42

    class Config:
        env_file = ".env"


@lru_cache
def get_training_settings() -> TrainingSettings:
    return TrainingSettings()

#0 is chainsaw, 1 is environment, but the label ot idx in notebook idk ta index is how work xia 
