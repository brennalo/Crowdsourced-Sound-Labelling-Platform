from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.database import get_db
from app.models.user import User
from app.models.segment import Segment
from app.models.recording import Recording
from app.schemas.segment import SegmentOut, MySegmentOut, ManualLabelCreate
from app.auth import get_current_user
from app.services.audio import generate_signed_url
import uuid

router = APIRouter(prefix="/segments", tags=["segments"])

VALID_STATUSES = {
    "annotation_pending", "suggestion_pending",
    "excluded_other", "training_pool", "consensus_open",
}


@router.get("/my", response_model=list[MySegmentOut])
async def list_my_segments(
    review_status: str | None = Query(None),
    recording_id: uuid.UUID | None = Query(None),
    sort: str = Query("confidence_asc"),  # confidence_asc | confidence_desc | time_asc | time_desc
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Contributor's own segments, optionally filtered by review_status.
    Default sort: confidence ascending (low-confidence / needs attention first).
    """
    query = (
        select(Segment, Recording.recorded_at.label("recording_recorded_at"))
        .join(Recording, Recording.id == Segment.recording_id)
        .where(Segment.user_id == current_user.id, Segment.is_silent == False)
    )

    if review_status:
        query = query.where(Segment.review_status == review_status)
    if recording_id:
        query = query.where(Segment.recording_id == recording_id)

    match sort:
        case "confidence_asc":
            query = query.order_by(Segment.model_confidence.asc().nulls_first())
        case "confidence_desc":
            query = query.order_by(Segment.model_confidence.desc().nulls_last())
        case "time_desc":
            query = query.order_by(Segment.created_at.desc())
        case _:
            query = query.order_by(Segment.created_at.asc())

    result = await db.execute(query)
    rows = result.all()

    output = []
    for segment, rec_recorded_at in rows:
        d = SegmentOut.model_validate(segment).model_dump()
        output.append(MySegmentOut(**d, recording_recorded_at=rec_recorded_at))
    return output


@router.patch("/my/{segment_id}/label", response_model=SegmentOut)
async def update_own_label(
    segment_id: uuid.UUID,
    body: ManualLabelCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Contributor edits the label on their own segment at any time.
    Works on annotation_pending, excluded_other, AND training_pool segments.
    Selecting 'other' moves segment to excluded_other and clears effective_label.
    """
    result = await db.execute(
        select(Segment).where(Segment.id == segment_id, Segment.user_id == current_user.id)
    )
    segment = result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")

    if body.label == "other":
        segment.review_status = "excluded_other"
        segment.effective_label = None
        segment.pool_entry_reason = None
    else:
        segment.effective_label = body.label
        segment.review_status = "training_pool"
        if segment.pool_entry_reason is None:
            segment.pool_entry_reason = "manual"

    await db.commit()
    await db.refresh(segment)
    return SegmentOut.model_validate(segment)


@router.get("/my/{segment_id}", response_model=SegmentOut)
async def get_my_segment(
    segment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Segment).where(Segment.id == segment_id, Segment.user_id == current_user.id)
    )
    segment = result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")
    return SegmentOut.model_validate(segment)


@router.get("/my/{segment_id}/audio-url")
async def get_my_segment_audio_url(
    segment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Segment).where(Segment.id == segment_id, Segment.user_id == current_user.id)
    )
    segment = result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")
    return {"url": generate_signed_url(segment.gcs_path), "expires_in_seconds": 3600}


@router.get("/{segment_id}/audio-url")
async def get_segment_audio_url(
    segment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Public audio URL endpoint — any authenticated user (for training pool / consensus playback)."""
    result = await db.execute(select(Segment).where(Segment.id == segment_id))
    segment = result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")
    return {"url": generate_signed_url(segment.gcs_path), "expires_in_seconds": 3600}
