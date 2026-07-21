# Programmer Name : Brenna Lo
# Program Name : suggestions.py
# Description : Suggestion API endpoints for managing model suggestions
# First Written on : 2024-06-10
# Edited on : 2024-07-18

"""
Suggestion review — high-confidence model predictions on contributor's own segments.
Contributor can: accept (model label stands) or reject+correct (pick correct label).
Both paths send segment to training_pool.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.user import User
from app.models.segment import Segment
from app.models.label import Label
from app.models.retraining_job import RetrainingJob
from app.schemas.segment import SegmentOut, SuggestionReviewCreate
from app.auth import get_current_user
from app.services.active_learning import count_rejections_since_last_retrain, should_trigger_retrain
from app.services.label_change import record_label_change
from app.workers.retraining import trigger_retrain_job
import uuid

router = APIRouter(prefix="/suggestions", tags=["suggestions"])


@router.get("/queue", response_model=list[SegmentOut])
async def get_suggestion_queue(
    limit: int = 30,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Own suggestion_pending segments sorted by confidence descending (most certain first)."""
    result = await db.execute(
        select(Segment)
        .where(
            Segment.user_id == current_user.id,
            Segment.review_status == "suggestion_pending",
            Segment.is_silent == False,
        )
        .order_by(Segment.model_confidence.desc())
        .limit(limit)
    )
    return [SegmentOut.model_validate(s) for s in result.scalars().all()]


@router.post("/{segment_id}/review", response_model=SegmentOut, status_code=status.HTTP_200_OK)
async def review_suggestion(
    segment_id: uuid.UUID,
    body: SuggestionReviewCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if body.decision == "rejected" and not body.corrected_label:
        raise HTTPException(status_code=400, detail="corrected_label is required when decision is 'rejected'")

    seg_result = await db.execute(
        select(Segment).where(Segment.id == segment_id, Segment.user_id == current_user.id)
    )
    segment = seg_result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")
    if segment.review_status != "suggestion_pending":
        raise HTTPException(status_code=409, detail="Segment is not awaiting suggestion review")

    if body.decision == "accepted":
        segment.effective_label = segment.model_label
        segment.pool_entry_reason = "accepted"
        rejection = False
    else:
        # Validate corrected label exists
        lbl = await db.execute(select(Label).where(Label.name == body.corrected_label, Label.is_active == True))
        if not lbl.scalar_one_or_none():
            raise HTTPException(status_code=400, detail=f"Unknown label: {body.corrected_label}")
        segment.effective_label = body.corrected_label
        segment.pool_entry_reason = "manual"
        rejection = True

    segment.review_status = "training_pool"

    if rejection:
        # old_label = what was rejected (the model's suggestion), not the prior
        # effective_label (which was still null at this point)
        await record_label_change(
            db,
            segment_id=segment.id,
            change_source="contributor_reject",
            old_label=segment.model_label,
            new_label=segment.effective_label,
            changed_by_user_id=current_user.id,
        )

    await db.commit()
    await db.refresh(segment)

    # Active learning trigger on rejection
    if rejection:
        count = await count_rejections_since_last_retrain(db)
        if await should_trigger_retrain(db, count):
            job = RetrainingJob(
                id=uuid.uuid4(),
                triggered_by="rejection_threshold",
                status="queued",
                rejection_count=count,
            )
            db.add(job)
            await db.commit()
            await db.refresh(job)
            trigger_retrain_job.delay(str(job.id))

    return SegmentOut.model_validate(segment)