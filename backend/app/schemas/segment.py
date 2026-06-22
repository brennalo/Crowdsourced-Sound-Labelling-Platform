from pydantic import BaseModel
from datetime import datetime
import uuid


class SegmentOut(BaseModel):
    id: uuid.UUID
    recording_id: uuid.UUID
    user_id: uuid.UUID
    gcs_path: str
    start_sec: float
    end_sec: float
    review_status: str
    created_at: datetime

    model_config = {"from_attributes": True}


class SegmentWithPrediction(SegmentOut):
    """Segment with model prediction attached — used in review queue."""
    predicted_label: str | None = None
    confidence: float | None = None
    annotation_id: uuid.UUID | None = None  # model annotation id, needed for review submission


class AnnotationCreate(BaseModel):
    label: str  # environment | chainsaw


class AnnotationOut(BaseModel):
    id: uuid.UUID
    segment_id: uuid.UUID
    user_id: uuid.UUID
    label: str
    source: str
    confidence: float | None
    created_at: datetime

    model_config = {"from_attributes": True}


class SuggestionReviewCreate(BaseModel):
    decision: str  # accepted | rejected


class SuggestionReviewOut(BaseModel):
    id: uuid.UUID
    segment_id: uuid.UUID
    decision: str
    reviewed_at: datetime

    model_config = {"from_attributes": True}
