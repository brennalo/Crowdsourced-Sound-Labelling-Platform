import uuid
from app.workers.celery_app import celery_app
from app.config import get_settings

settings = get_settings()


@celery_app.task(bind=True, max_retries=2, default_retry_delay=30)
def trigger_retrain_job(self, retraining_job_id: str):
    """
    Triggers a Cloud Run Job to perform full model retraining.
    Updates retraining_job status in DB throughout.
    """
    import asyncio
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        loop.run_until_complete(_trigger_retrain_job(retraining_job_id))
    finally:
        loop.close()


async def _trigger_retrain_job(retraining_job_id: str):
    import httpx
    from datetime import datetime, timezone
    from sqlalchemy import select
    from app.database import AsyncSessionLocal
    from app.models.retraining_job import RetrainingJob

    job_uuid = uuid.UUID(retraining_job_id)

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(RetrainingJob).where(RetrainingJob.id == job_uuid))
        job = result.scalar_one_or_none()
        if not job:
            print(f"[retraining] Job {retraining_job_id} not found")
            return

        job.status = "running"
        await db.commit()

        try:
            # Get access token for GCP API call
            token = await _get_gcp_access_token()

            # Trigger Cloud Run Job via GCP REST API
            url = (
                f"https://run.googleapis.com/v2/projects/{settings.gcp_project_id}"
                f"/locations/{settings.gcp_region}/jobs/{settings.retrain_job_name}:run"
            )

            async with httpx.AsyncClient(timeout=30) as client:
                response = await client.post(
                    url,
                    headers={"Authorization": f"Bearer {token}"},
                    json={
                        "overrides": {
                            "containerOverrides": [{
                                "env": [
                                    {"name": "RETRAINING_JOB_ID", "value": retraining_job_id},
                                    {"name": "DATABASE_URL", "value": settings.database_url},
                                    {"name": "GCS_BUCKET_NAME", "value": settings.gcs_bucket_name},
                                    {"name": "MODEL_GCS_PREFIX", "value": settings.model_gcs_prefix},
                                ]
                            }]
                        }
                    },
                )
                response.raise_for_status()

            print(f"[retraining] Cloud Run Job triggered for job {retraining_job_id}")
            # Note: job status is set to "done" by the training container itself when complete

        except Exception as e:
            result = await db.execute(select(RetrainingJob).where(RetrainingJob.id == job_uuid))
            job = result.scalar_one_or_none()
            if job:
                job.status = "failed"
                job.error_log = str(e)
                job.completed_at = datetime.now(timezone.utc)
                await db.commit()
            raise e


async def _get_gcp_access_token() -> str:
    """Fetch GCP access token from metadata server (works on Cloud Run)."""
    import httpx
    async with httpx.AsyncClient() as client:
        response = await client.get(
            "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
            headers={"Metadata-Flavor": "Google"},
            timeout=5,
        )
        response.raise_for_status()
        return response.json()["access_token"]
