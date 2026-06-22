from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.user import User
from app.models.segment import Segment
from app.models.annotation import Annotation
from app.schemas.segment import AnnotationCreate, AnnotationOut
from app.auth import get_current_user
import uuid

router = APIRouter(prefix="/annotations", tags=["annotations"])

VALID_LABELS = {"environment", "chainsaw"}


@router.post("/{segment_id}", response_model=AnnotationOut, status_code=status.HTTP_201_CREATED)
async def annotate_segment(
    segment_id: uuid.UUID,
    body: AnnotationCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if body.label not in VALID_LABELS:
        raise HTTPException(status_code=400, detail=f"Invalid label. Must be one of: {VALID_LABELS}")

    # Verify segment belongs to current user
    result = await db.execute(
        select(Segment).where(Segment.id == segment_id, Segment.user_id == current_user.id)
    )
    segment = result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")

    if segment.review_status == "annotated":
        raise HTTPException(status_code=409, detail="Segment already annotated")

    annotation = Annotation(
        id=uuid.uuid4(),
        segment_id=segment_id,
        user_id=current_user.id,
        label=body.label,
        source="manual",
        confidence=None,
    )
    db.add(annotation)

    segment.review_status = "annotated"
    await db.commit()
    await db.refresh(annotation)

    return AnnotationOut.model_validate(annotation)


@router.get("/{segment_id}", response_model=list[AnnotationOut])
async def get_segment_annotations(
    segment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Verify ownership
    seg_result = await db.execute(
        select(Segment).where(Segment.id == segment_id, Segment.user_id == current_user.id)
    )
    if not seg_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Segment not found")

    result = await db.execute(
        select(Annotation).where(Annotation.segment_id == segment_id).order_by(Annotation.created_at)
    )
    return [AnnotationOut.model_validate(a) for a in result.scalars().all()]
