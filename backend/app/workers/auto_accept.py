"""
Periodic task: auto-accept suggestion_pending segments older than 7 days.
annotation_pending segments are never auto-accepted.
Run via Celery Beat — add to celery_app beat_schedule.
"""
from app.workers.celery_app import celery_app


@celery_app.task
def auto_accept_old_suggestions():
    import asyncio
    asyncio.run(_auto_accept())


async def _auto_accept():
    from datetime import datetime, timezone, timedelta
    from sqlalchemy import select
    from app.database import AsyncSessionLocal
    from app.models.segment import Segment

    cutoff = datetime.now(timezone.utc) - timedelta(days=7)

    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Segment).where(
                Segment.review_status == "suggestion_pending",
                Segment.created_at <= cutoff,
                Segment.is_silent == False,
            )
        )
        segments = result.scalars().all()

        for seg in segments:
            seg.effective_label = seg.model_label
            seg.review_status = "training_pool"
            seg.pool_entry_reason = "auto_7day"

        await db.commit()
        print(f"[auto_accept] Auto-accepted {len(segments)} segments older than 7 days")
