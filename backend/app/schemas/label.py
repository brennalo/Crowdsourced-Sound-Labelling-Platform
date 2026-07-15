import uuid
from datetime import datetime
from pydantic import BaseModel


class LabelOut(BaseModel):
    id: uuid.UUID
    name: str
    display_name: str
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class LabelCreate(BaseModel):
    name: str
    display_name: str


class LabelUpdate(BaseModel):
    is_active: bool


class LabelChangeOut(BaseModel):
    id: uuid.UUID
    segment_id: uuid.UUID
    changed_by_user_id: uuid.UUID | None
    change_source: str
    old_label: str | None
    new_label: str | None
    changed_at: datetime

    model_config = {"from_attributes": True}