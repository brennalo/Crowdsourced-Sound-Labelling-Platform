from celery import Celery
from celery.schedules import crontab
from celery.signals import worker_process_init
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
@worker_process_init.connect
def load_model_on_worker_start(**kwargs):
    import asyncio
    from sqlalchemy import select
    from app.database import AsyncSessionLocal, engine  # import the engine too
    from app.models.model_version import ModelVersion
    from app.services.inference import load_active_model_from_gcs

    async def _load():
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(ModelVersion).where(ModelVersion.is_active == True)
            )
            active_model = result.scalar_one_or_none()
            if active_model:
                load_active_model_from_gcs(active_model.gcs_model_path)
                print(f"[worker startup] Loaded model {active_model.version_tag}")
            else:
                print("[worker startup] No active model registered — inference disabled")

    try:
        asyncio.run(_load())
    except Exception as e:
        print(f"[worker startup] Warning: could not load model — {e}")