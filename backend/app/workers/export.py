import uuid
from app.workers.celery_app import celery_app


@celery_app.task(bind=True, max_retries=2, default_retry_delay=60)
def run_export_job(self, export_job_id: str):
    import asyncio
    # Create a brand new event loop each time — never reuse
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        loop.run_until_complete(_run_export_job(export_job_id))
    finally:
        loop.close()


async def _run_export_job(export_job_id: str):
    from datetime import datetime, timezone
    from sqlalchemy import select
    from sqlalchemy.orm import joinedload
    from app.database import AsyncSessionLocal
    from app.models.export_job import ExportJob
    from app.models.segment import Segment
    from app.services.export import build_export_zip

    job_uuid = uuid.UUID(export_job_id)

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(ExportJob).where(ExportJob.id == job_uuid))
        job = result.scalar_one_or_none()
        if not job:
            return

        try:
            # Training export: authoritative label set, effective_label is the
            # single source of truth (annotations table has been removed)
            seg_result = await db.execute(
                select(Segment).where(
                    Segment.review_status == "training_pool",
                    Segment.effective_label.isnot(None),
                    Segment.is_silent == False,
                )
            )
            segments = seg_result.scalars().all()

            annotated_segments = [
                {
                    "segment_id": str(segment.id),
                    "gcs_path": segment.gcs_path,
                    "label": segment.effective_label,
                }
                for segment in segments
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

            from app.services.push import send_push_to_user
            await send_push_to_user(
                db,
                user_id=job.requested_by,
                data={"type": "export_done", "export_job_id": export_job_id},
                notification={
                    "title": "Export ready",
                    "body": "Your dataset export has finished and is ready to download.",
                },
            )

        except Exception as e:
            result = await db.execute(select(ExportJob).where(ExportJob.id == job_uuid))
            job = result.scalar_one_or_none()
            if job:
                job.status = "failed"
                job.error_log = str(e)
                job.completed_at = datetime.now(timezone.utc)
                await db.commit()
            raise e