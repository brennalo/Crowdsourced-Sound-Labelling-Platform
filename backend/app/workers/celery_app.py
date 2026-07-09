from celery import Celery
from celery.schedules import crontab
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
        "app.workers.auto_accept",
    ],
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    # Beat schedule: run auto-accept once per day at 02:00 UTC
    beat_schedule={
        "auto-accept-old-suggestions": {
            "task": "app.workers.auto_accept.auto_accept_old_suggestions",
            "schedule": crontab(hour=2, minute=0),
        },
    },
)
