from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.user import User
from app.models.segment import Segment
from app.schemas.segment import SegmentOut
from app.auth import get_current_user
from app.services.audio import generate_signed_url
import uuid

router = APIRouter(prefix="/segments", tags=["segments"])


@router.get("/", response_model=list[SegmentOut])
async def list_my_segments(
    recording_id: uuid.UUID | None = None,
    review_status: str | None = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = select(Segment).where(Segment.user_id == current_user.id, Segment.is_silent == False)

    if recording_id:
        query = query.where(Segment.recording_id == recording_id)
    if review_status:
        query = query.where(Segment.review_status == review_status)

    query = query.order_by(Segment.created_at.asc())
    result = await db.execute(query)
    return [SegmentOut.model_validate(s) for s in result.scalars().all()]


@router.get("/{segment_id}", response_model=SegmentOut)
async def get_segment(
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


@router.get("/{segment_id}/audio-url")
async def get_segment_audio_url(
    segment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Returns a short-lived signed GCS URL so Flutter can stream the audio."""
    result = await db.execute(
        select(Segment).where(Segment.id == segment_id, Segment.user_id == current_user.id)
    )
    segment = result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")

    url = generate_signed_url(segment.gcs_path)
    return {"url": url, "expires_in_seconds": 3600}
