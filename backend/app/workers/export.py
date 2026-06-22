import uuid
from app.workers.celery_app import celery_app


@celery_app.task(bind=True, max_retries=2, default_retry_delay=60)
def run_export_job(self, export_job_id: str):
    import asyncio
    asyncio.run(_run_export_job(export_job_id))


async def _run_export_job(export_job_id: str):
    from datetime import datetime, timezone
    from sqlalchemy import select
    from sqlalchemy.orm import joinedload
    from app.database import AsyncSessionLocal
    from app.models.export_job import ExportJob
    from app.models.annotation import Annotation
    from app.models.segment import Segment
    from app.services.export import build_export_zip

    job_uuid = uuid.UUID(export_job_id)

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(ExportJob).where(ExportJob.id == job_uuid))
        job = result.scalar_one_or_none()
        if not job:
            return

        try:
            # Fetch all manually annotated, non-silent segments
            ann_result = await db.execute(
                select(Annotation, Segment)
                .join(Segment, Annotation.segment_id == Segment.id)
                .where(
                    Annotation.source == "manual",
                    Segment.is_silent == False,
                )
            )
            rows = ann_result.all()

            annotated_segments = [
                {
                    "segment_id": str(annotation.id),
                    "gcs_path": segment.gcs_path,
                    "label": annotation.label,
                }
                for annotation, segment in rows
            ]

            if not annotated_segments:
                job.status = "failed"
                job.error_log = "No annotated segments found"
                job.completed_at = datetime.now(timezone.utc)
                await db.commit()
                return

            print(f"[export] Building zip for {len(annotated_segments)} segments")
            gcs_zip_path = build_export_zip(annotated_segments, job_uuid)

            job.status = "done"
            job.gcs_export_path = gcs_zip_path
            job.completed_at = datetime.now(timezone.utc)
            await db.commit()

            print(f"[export] Done — {gcs_zip_path}")

        except Exception as e:
            result = await db.execute(select(ExportJob).where(ExportJob.id == job_uuid))
            job = result.scalar_one_or_none()
            if job:
                job.status = "failed"
                job.error_log = str(e)
                job.completed_at = datetime.now(timezone.utc)
                await db.commit()
            raise e
