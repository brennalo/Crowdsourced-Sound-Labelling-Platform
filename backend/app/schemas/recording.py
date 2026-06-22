from pydantic import BaseModel
from datetime import datetime
import uuid


class RecordingCreate(BaseModel):
    recorded_at: datetime | None = None
    location_lat: float | None = None
    location_lng: float | None = None


class RecordingOut(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    gcs_raw_path: str
    duration_sec: float | None
    recorded_at: datetime | None
    location_lat: float | None
    location_lng: float | None
    status: str
    created_at: datetime

    model_config = {"from_attributes": True}
