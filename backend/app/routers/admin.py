# Programmer Name : Brenna Lo
# Program Name : admin.py
# Description : Admin API endpoints for user and segment management
# First Written on : 2024-06-10
# Edited on : 2024-07-18

"""
User deletion is a SOFT delete (is_active=False)
Segment deletion (from the Segments tab) IS a hard delete
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from datetime import datetime, timezone
from app.database import get_db
from app.models.user import User
from app.models.recording import Recording
from app.models.segment import Segment
from app.models.consensus_vote import ConsensusVote
from app.models.label_change import LabelChange
from app.schemas.admin import AdminUserOut, AdminSegmentOut
from app.auth import require_admin
import uuid

router = APIRouter(prefix="/admin", tags=["admin"])


# ── Users (Contributors / Researchers tabs) ─────────────────────

@router.get("/users", response_model=list[AdminUserOut])
async def list_users(
    role: str | None = Query(None, description="contributor | researcher | admin"),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_admin),
):
    query = select(User).order_by(User.created_at.desc())
    if role:
        query = query.where(User.role == role)
    result = await db.execute(query)
    users = result.scalars().all()

    if not users:
        return []

    user_ids = [u.id for u in users]

    rec_counts_result = await db.execute(
        select(Recording.user_id, func.count().label("n"))
        .where(Recording.user_id.in_(user_ids))
        .group_by(Recording.user_id)
    )
    rec_counts = {row.user_id: row.n for row in rec_counts_result}

    seg_counts_result = await db.execute(
        select(Segment.user_id, func.count().label("n"))
        .where(Segment.user_id.in_(user_ids))
        .group_by(Segment.user_id)
    )
    seg_counts = {row.user_id: row.n for row in seg_counts_result}

    return [
        AdminUserOut(
            id=u.id,
            email=u.email,
            display_name=u.display_name,
            role=u.role,
            is_active=u.is_active,
            deactivated_at=u.deactivated_at,
            created_at=u.created_at,
            recordings_count=rec_counts.get(u.id, 0),
            segments_count=seg_counts.get(u.id, 0),
        )
        for u in users
    ]


@router.delete("/users/{user_id}", status_code=status.HTTP_200_OK)
async def deactivate_user(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Soft delete — deactivates the account. Their data is left untouched."""
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="You can't deactivate your own account")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.is_active = False
    user.deactivated_at = datetime.now(timezone.utc)
    await db.commit()
    return {"detail": "User deactivated", "user_id": str(user_id)}


@router.post("/users/{user_id}/reactivate", status_code=status.HTTP_200_OK)
async def reactivate_user(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_admin),
):
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.is_active = True
    user.deactivated_at = None
    await db.commit()
    return {"detail": "User reactivated", "user_id": str(user_id)}


# ── Segments tab ─────────────────────────────────────────────────

@router.get("/segments", response_model=list[AdminSegmentOut])
async def list_all_segments(
    limit: int = Query(50, le=200),
    offset: int = Query(0),
    review_status: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_admin),
):
    query = (
        select(Segment, User.display_name.label("uploader_name"), User.email.label("uploader_email"))
        .join(User, User.id == Segment.user_id)
        .where(Segment.is_silent == False)
        .order_by(Segment.created_at.desc())
    )
    if review_status:
        query = query.where(Segment.review_status == review_status)
    query = query.offset(offset).limit(limit)

    result = await db.execute(query)
    rows = result.all()

    return [
        AdminSegmentOut(
            id=seg.id,
            recording_id=seg.recording_id,
            uploader_display_name=uploader_name,
            uploader_email=uploader_email,
            review_status=seg.review_status,
            effective_label=seg.effective_label,
            sequence_num=seg.sequence_num,
            created_at=seg.created_at,
        )
        for seg, uploader_name, uploader_email in rows
    ]


@router.delete("/segments/{segment_id}", status_code=status.HTTP_200_OK)
async def delete_segment(
    segment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_admin),
):
    """Hard delete — removes the segment and its votes/audit trail. Does NOT
    delete the underlying GCS audio file; that's fine, it's an orphaned
    object at that point and cheap to leave for later cleanup."""
    result = await db.execute(select(Segment).where(Segment.id == segment_id))
    segment = result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")

    await db.execute(ConsensusVote.__table__.delete().where(ConsensusVote.segment_id == segment_id))
    await db.execute(LabelChange.__table__.delete().where(LabelChange.segment_id == segment_id))
    await db.delete(segment)
    await db.commit()
    return {"detail": "Segment deleted", "segment_id": str(segment_id)}
