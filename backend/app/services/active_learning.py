from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.models.suggestion_review import SuggestionReview
from app.models.retraining_job import RetrainingJob
from app.config import get_settings

settings = get_settings()


async def count_rejections_since_last_retrain(db: AsyncSession) -> int:
    """
    Count rejected suggestions since the last completed retraining job.
    If no retrain has ever happened, counts all rejections.
    """
    # Find the most recent completed retrain
    last_retrain_result = await db.execute(
        select(RetrainingJob)
        .where(RetrainingJob.status == "done")
        .order_by(RetrainingJob.completed_at.desc())
        .limit(1)
    )
    last_retrain = last_retrain_result.scalar_one_or_none()

    query = select(func.count()).select_from(SuggestionReview).where(
        SuggestionReview.decision == "rejected"
    )

    if last_retrain and last_retrain.completed_at:
        query = query.where(SuggestionReview.reviewed_at > last_retrain.completed_at)

    result = await db.execute(query)
    return result.scalar_one()


async def should_trigger_retrain(db: AsyncSession, rejection_count: int) -> bool:
    """
    Returns True if rejection count hits threshold AND no retrain is currently queued/running.
    Prevents duplicate jobs being enqueued.
    """
    if rejection_count < settings.rejection_threshold:
        return False

    # Check if a job is already in progress
    in_progress = await db.execute(
        select(RetrainingJob).where(RetrainingJob.status.in_(["queued", "running"]))
    )
    if in_progress.scalar_one_or_none():
        return False

    return True
