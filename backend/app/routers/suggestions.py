from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.database import get_db
from app.models.user import User
from app.models.segment import Segment
from app.models.annotation import Annotation
from app.models.suggestion_review import SuggestionReview
from app.models.retraining_job import RetrainingJob
from app.schemas.segment import SegmentWithPrediction, SuggestionReviewCreate, SuggestionReviewOut
from app.auth import get_current_user
from app.services.inference import get_inference_service
from app.services.active_learning import count_rejections_since_last_retrain, should_trigger_retrain
from app.workers.retraining import trigger_retrain_job
import uuid

router = APIRouter(prefix="/suggestions", tags=["suggestions"])


@router.get("/queue", response_model=list[SegmentWithPrediction])
async def get_suggestion_queue(
    limit: int = 20,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Returns segments that the model has predicted but flagged as low confidence,
    needing human review. Only returns segments belonging to the current user.
    """
    result = await db.execute(
        select(Segment)
        .where(
            Segment.user_id == current_user.id,
            Segment.review_status == "pending",
            Segment.is_silent == False,
        )
        .order_by(Segment.created_at.asc())
        .limit(limit)
    )
    segments = result.scalars().all()

    inference = get_inference_service()
    output = []

    for segment in segments:
        # Check if model annotation already exists for this segment
        ann_result = await db.execute(
            select(Annotation).where(
                Annotation.segment_id == segment.id,
                Annotation.source == "model",
            )
        )
        model_annotation = ann_result.scalar_one_or_none()

        if model_annotation:
            output.append(SegmentWithPrediction(
                **SegmentWithPrediction.model_validate(segment).model_dump(),
                predicted_label=model_annotation.label,
                confidence=model_annotation.confidence,
                annotation_id=model_annotation.id,
            ))
        else:
            # Run inference and store result
            prediction = await inference.predict_from_gcs(segment.gcs_path)
            if prediction is None:
                continue

            new_annotation = Annotation(
                id=uuid.uuid4(),
                segment_id=segment.id,
                user_id=current_user.id,
                label=prediction["label"],
                source="model",
                confidence=prediction["confidence"],
            )
            db.add(new_annotation)
            await db.flush()

            output.append(SegmentWithPrediction(
                **SegmentWithPrediction.model_validate(segment).model_dump(),
                predicted_label=prediction["label"],
                confidence=prediction["confidence"],
                annotation_id=new_annotation.id,
            ))

    await db.commit()
    return output


@router.post("/{segment_id}/review", response_model=SuggestionReviewOut, status_code=status.HTTP_201_CREATED)
async def review_suggestion(
    segment_id: uuid.UUID,
    body: SuggestionReviewCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if body.decision not in {"accepted", "rejected"}:
        raise HTTPException(status_code=400, detail="Decision must be 'accepted' or 'rejected'")

    # Verify segment ownership
    seg_result = await db.execute(
        select(Segment).where(Segment.id == segment_id, Segment.user_id == current_user.id)
    )
    segment = seg_result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")

    # Get the model annotation for this segment
    ann_result = await db.execute(
        select(Annotation).where(Annotation.segment_id == segment_id, Annotation.source == "model")
    )
    model_annotation = ann_result.scalar_one_or_none()
    if not model_annotation:
        raise HTTPException(status_code=404, detail="No model prediction found for this segment")

    # Prevent duplicate review
    existing = await db.execute(
        select(SuggestionReview).where(
            SuggestionReview.segment_id == segment_id,
            SuggestionReview.user_id == current_user.id,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Already reviewed this suggestion")

    review = SuggestionReview(
        id=uuid.uuid4(),
        segment_id=segment_id,
        user_id=current_user.id,
        annotation_id=model_annotation.id,
        decision=body.decision,
    )
    db.add(review)

    # Update segment status
    segment.review_status = "accepted_suggestion" if body.decision == "accepted" else "rejected_suggestion"
    await db.commit()
    await db.refresh(review)

    # Check active learning trigger after rejection
    if body.decision == "rejected":
        rejection_count = await count_rejections_since_last_retrain(db)
        if await should_trigger_retrain(db, rejection_count):
            job = RetrainingJob(
                id=uuid.uuid4(),
                triggered_by="rejection_threshold",
                status="queued",
                rejection_count=rejection_count,
            )
            db.add(job)
            await db.commit()
            await db.refresh(job)
            trigger_retrain_job.delay(str(job.id))

    return SuggestionReviewOut.model_validate(review)
