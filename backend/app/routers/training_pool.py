# Programmer Name : Brenna Lo
# Program Name : training_pool.py
# Description : Training pool API endpoints for managing training segments
# First Written on : 2024-06-10
# Edited on : 2024-07-18

"""
Training pool — read-only view of all training_pool + consensus_open segments.
All authenticated users can browse and listen.
Contributors can report (opens consensus).
Researchers can directly override labels.
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.database import get_db
from app.models.user import User
from app.models.segment import Segment
from app.models.recording import Recording
from app.models.consensus_vote import ConsensusVote
from app.schemas.segment import TrainingPoolSegmentOut, SegmentOut
from app.auth import get_current_user
import uuid

router = APIRouter(prefix="/training-pool", tags=["training-pool"])

_POOL_STATUSES = {"training_pool", "consensus_open"}


@router.get("/", response_model=list[TrainingPoolSegmentOut])
async def list_training_pool(
    sort: str = Query("time_desc"),   # time_desc | time_asc | confidence_asc | confidence_desc
    label: str | None = Query(None),  # filter by effective_label
    limit: int = Query(50, le=200),
    offset: int = Query(0),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    query = (
        select(
            Segment,
            User.display_name.label("uploader_name"),
            Recording.recorded_at.label("recording_recorded_at"),
            Recording.total_segments.label("recording_total_segments"),
        )
        .join(User, User.id == Segment.user_id)
        .outerjoin(Recording, Recording.id == Segment.recording_id)
        .where(Segment.review_status.in_(_POOL_STATUSES), Segment.is_silent == False)
    )

    if label:
        query = query.where(Segment.effective_label == label)

    match sort:
        case "confidence_asc":
            query = query.order_by(Segment.model_confidence.asc().nulls_first())
        case "confidence_desc":
            query = query.order_by(Segment.model_confidence.desc().nulls_last())
        case "time_asc":
            query = query.order_by(Segment.created_at.asc())
        case _:
            query = query.order_by(Segment.created_at.desc())

    query = query.offset(offset).limit(limit)
    result = await db.execute(query)
    rows = result.all()

    seg_ids = [seg.id for seg, *_ in rows]
    vote_counts_result = await db.execute(
        select(ConsensusVote.segment_id, ConsensusVote.verdict, func.count().label("n"))
        .where(ConsensusVote.segment_id.in_(seg_ids))
        .group_by(ConsensusVote.segment_id, ConsensusVote.verdict)
    )
    vote_counts: dict[uuid.UUID, dict] = {}
    for seg_id, verdict, n in vote_counts_result:
        vote_counts.setdefault(seg_id, {})[verdict] = n

    output = []
    for segment, uploader_name, rec_recorded_at, rec_total_segments in rows:
        base = SegmentOut.model_validate(segment).model_dump()
        c = vote_counts.get(segment.id, {})
        output.append(TrainingPoolSegmentOut(
            **base,
            uploader_display_name=uploader_name,
            agree_count=c.get("agree", 0),
            disagree_count=c.get("disagree", 0),
            consensus_open=segment.review_status == "consensus_open",
            recording_recorded_at=rec_recorded_at,
            recording_total_segments=rec_total_segments,
        ))
    return output
