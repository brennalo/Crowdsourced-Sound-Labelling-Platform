# Programmer Name : Brenna Lo
# Program Name : active_learning.py
# Description : Active learning logic for managing model suggestions and retraining as helper funtions class
# First Written on : 2024-06-10
# Edited on : 2024-07-18

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.models.label_change import LabelChange
from app.models.retraining_job import RetrainingJob
from app.services.system_config import get_system_config


async def count_rejections_since_last_retrain(db: AsyncSession) -> int:
    """
    Count contributor rejections logged in label_changes since the last completed retrain.
    Uses LabelChange.changed_at (the actual moment of rejection) rather than
    Segment.created_at (when the segment was uploaded), since a segment can be
    rejected long after it was created.
    If no retrain has ever happened, counts all rejections on record.
    """
    last_retrain_result = await db.execute(
        select(RetrainingJob)
        .where(RetrainingJob.status == "done")
        .order_by(RetrainingJob.completed_at.desc())
        .limit(1)
    )
    last_retrain = last_retrain_result.scalar_one_or_none()

    query = (
        select(func.count())
        .select_from(LabelChange)
        .where(LabelChange.change_source == "contributor_reject")
    )

    if last_retrain and last_retrain.completed_at:
        query = query.where(LabelChange.changed_at > last_retrain.completed_at)

    result = await db.execute(query)
    return result.scalar_one()


async def should_trigger_retrain(db: AsyncSession, rejection_count: int) -> bool:
    """
    Returns True if rejection count hits threshold AND no retrain is currently queued/running.
    """
    config = await get_system_config(db)
    if rejection_count < config.rejection_threshold:
        return False

    in_progress = await db.execute(
        select(RetrainingJob).where(RetrainingJob.status.in_(["queued", "running"]))
    )
    if in_progress.scalar_one_or_none():
        return False

    return True