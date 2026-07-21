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
conf_updates = dict(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    beat_schedule={
        "auto-accept-old-suggestions": {
            "task": "app.workers.auto_accept.auto_accept_old_suggestions",
            "schedule": crontab(hour=2, minute=0),
        },
        "reap-stale-retraining-jobs": {
        "task": "app.workers.retraining.reap_stale_retraining_jobs",
        "schedule": crontab(minute="*/15"),  # every 15 min, not once-daily like the nightly sweep
        },
    },
    broker_connection_retry_on_startup=True,
    broker_connection_retry=True,
    broker_connection_max_retries=None,
    broker_transport_options={
        'socket_keepalive': True,
        'socket_connect_timeout': 30,
        'retry_on_timeout': True,
        'health_check_interval': 120,
    },
    broker_pool_limit=1,
)

# Only add SSL params if actually connecting over rediss://
if settings.redis_url.startswith("rediss://"):
    conf_updates["broker_use_ssl"] = {'ssl_cert_reqs': 'CERT_NONE'}
    conf_updates["redis_backend_use_ssl"] = {'ssl_cert_reqs': 'CERT_NONE'}

celery_app.conf.update(**conf_updates)

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