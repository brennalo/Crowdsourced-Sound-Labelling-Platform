from pydantic import BaseModel
from datetime import datetime
import uuid


class AdminUserOut(BaseModel):
    id: uuid.UUID
    email: str
    display_name: str | None
    role: str
    is_active: bool
    deactivated_at: datetime | None
    created_at: datetime
    recordings_count: int
    segments_count: int

    model_config = {"from_attributes": True}


class AdminSegmentOut(BaseModel):
    id: uuid.UUID
    recording_id: uuid.UUID
    uploader_display_name: str | None
    uploader_email: str
    review_status: str
    effective_label: str | None
    sequence_num: int | None
    created_at: datetime

    model_config = {"from_attributes": True}
