"""
Researcher-only endpoints:
- GET  /researcher/queue          random 20 from training pool not yet reviewed by this researcher
- POST /researcher/review/{id}    confirm or correct a segment label (immediate, no consensus)
- POST /researcher/retrain        manually trigger model retrain
- GET  /researcher/stats          export statistics
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, text
from sqlalchemy.orm import selectinload
from datetime import datetime, timezone, timedelta
from app.database import get_db
from app.models.user import User
from app.models.segment import Segment
from app.models.label import Label
from app.models.researcher_review import ResearcherReview
from app.models.retraining_job import RetrainingJob
from app.schemas.segment import (
    SegmentOut, ResearcherReviewCreate, ResearcherReviewOut, ExportStatsOut
)
from app.auth import require_researcher
from app.workers.retraining import trigger_retrain_job
import uuid

router = APIRouter(prefix="/researcher", tags=["researcher"])

QUEUE_SIZE = 20
_POOL_STATUSES = {"training_pool", "consensus_open"}


@router.get("/queue", response_model=list[SegmentOut])
async def get_researcher_queue(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_researcher),
):
    """
    Returns up to 20 random training_pool segments not yet reviewed by this researcher.
    Each refresh replaces reviewed items with new random picks.
    """
    already_reviewed = (
        select(ResearcherReview.segment_id)
        .where(ResearcherReview.researcher_id == current_user.id)
        .scalar_subquery()
    )

    result = await db.execute(
        select(Segment)
        .where(
            Segment.review_status.in_(_POOL_STATUSES),
            Segment.is_silent == False,
            Segment.id.notin_(already_reviewed),
        )
        .order_by(func.random())
        .limit(QUEUE_SIZE)
    )
    return [SegmentOut.model_validate(s) for s in result.scalars().all()]


@router.post("/review/{segment_id}", response_model=ResearcherReviewOut, status_code=status.HTTP_201_CREATED)
async def submit_researcher_review(
    segment_id: uuid.UUID,
    body: ResearcherReviewCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_researcher),
):
    """
    Researcher confirms or corrects a segment. Direct final say — no consensus needed.
    Corrected segments have their effective_label updated immediately.
    """
    if body.action == "corrected" and not body.corrected_label:
        raise HTTPException(status_code=400, detail="corrected_label required when action is 'corrected'")

    seg_result = await db.execute(select(Segment).where(Segment.id == segment_id))
    segment = seg_result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")
    if segment.review_status not in _POOL_STATUSES:
        raise HTTPException(status_code=409, detail="Segment is not in the training pool")

    if body.action == "corrected":
        # Validate label
        lbl = await db.execute(
            select(Label).where(Label.name == body.corrected_label, Label.is_active == True)
        )
        if not lbl.scalar_one_or_none():
            raise HTTPException(status_code=400, detail=f"Unknown label: {body.corrected_label}")

        segment.effective_label = body.corrected_label
        # If it was in consensus, researcher correction closes the vote
        if segment.review_status == "consensus_open":
            segment.review_status = "training_pool"

    rr = ResearcherReview(
        id=uuid.uuid4(),
        segment_id=segment_id,
        researcher_id=current_user.id,
        action=body.action,
        corrected_label=body.corrected_label if body.action == "corrected" else None,
    )
    db.add(rr)
    await db.commit()
    await db.refresh(rr)
    return ResearcherReviewOut.model_validate(rr)


@router.post("/retrain", status_code=status.HTTP_201_CREATED)
async def manual_retrain(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_researcher),
):
    """Researcher manually triggers a retrain job."""
    in_progress = await db.execute(
        select(RetrainingJob).where(RetrainingJob.status.in_(["queued", "running"]))
    )
    if in_progress.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="A retraining job is already queued or running")

    job = RetrainingJob(
        id=uuid.uuid4(),
        triggered_by="manual",
        status="queued",
        rejection_count=None,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)
    trigger_retrain_job.delay(str(job.id))
    return {"job_id": str(job.id), "status": "queued"}


@router.get("/stats", response_model=ExportStatsOut)
async def get_export_stats(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_researcher),
):
    """Statistics shown on the export screen."""
    from app.models.consensus_vote import ConsensusVote

    # Total in pool
    total = await db.execute(
        select(func.count()).where(
            Segment.review_status.in_({"training_pool", "consensus_open"}),
            Segment.is_silent == False,
        )
    )
    total_in_pool = total.scalar_one()

    # Label distribution
    dist_result = await db.execute(
        select(Segment.effective_label, func.count().label("n"))
        .where(Segment.review_status.in_({"training_pool", "consensus_open"}))
        .group_by(Segment.effective_label)
    )
    label_distribution = {row.effective_label or "unknown": row.n for row in dist_result}

    # Consensus flips = disagree-won consensus rounds (approximate: segments whose
    # effective_label != model_label and pool_entry_reason is not 'manual')
    flips = await db.execute(
        select(func.count()).where(
            Segment.effective_label != Segment.model_label,
            Segment.pool_entry_reason != "manual",
            Segment.review_status.in_({"training_pool", "consensus_open"}),
        )
    )
    consensus_flips = flips.scalar_one()

    # Researcher corrections
    corrections = await db.execute(
        select(func.count()).select_from(ResearcherReview).where(
            ResearcherReview.action == "corrected"
        )
    )
    researcher_corrections = corrections.scalar_one()

    # Added in last 7 days
    week_ago = datetime.now(timezone.utc) - timedelta(days=7)
    recent = await db.execute(
        select(func.count()).where(
            Segment.review_status.in_({"training_pool", "consensus_open"}),
            Segment.created_at >= week_ago,
        )
    )
    added_last_7_days = recent.scalar_one()

    return ExportStatsOut(
        total_in_pool=total_in_pool,
        label_distribution=label_distribution,
        consensus_flips=consensus_flips,
        researcher_corrections=researcher_corrections,
        added_last_7_days=added_last_7_days,
    )
