from celery import Celery
from app.config import get_settings

settings = get_settings()

celery_app = Celery(
    "forest_sound",
    broker=settings.redis_url,
    backend=settings.redis_url,
    include=[
        "app.workers.segmentation",
        "app.workers.retraining",
        "app.workers.export",
    ],
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    task_acks_late=True,
    worker_prefetch_multiplier=1,  # one task at a time per worker — audio processing is CPU heavy
    broker_use_ssl={"ssl_cert_reqs": "CERT_NONE"} if settings.redis_url.startswith("rediss://") else {},
)
