from pydantic import BaseModel, Field
from datetime import datetime
import uuid


class SystemConfigOut(BaseModel):
    silence_threshold_dbfs: float
    confidence_threshold: float
    rejection_threshold: int
    updated_by: uuid.UUID | None
    updated_at: datetime

    model_config = {"from_attributes": True}


class SystemConfigUpdate(BaseModel):
    """All fields optional — PATCH semantics, only send what you're changing."""
    silence_threshold_dbfs: float | None = Field(None, le=0.0)
    confidence_threshold: float | None = Field(None, gt=0.0, le=1.0)
    rejection_threshold: int | None = Field(None, gt=0)
