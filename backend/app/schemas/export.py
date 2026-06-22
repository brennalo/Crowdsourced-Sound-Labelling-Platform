from pydantic import BaseModel
from datetime import datetime
import uuid


class ExportJobOut(BaseModel):
    id: uuid.UUID
    status: str
    gcs_export_path: str | None
    requested_at: datetime
    completed_at: datetime | None

    model_config = {"from_attributes": True}


class ExportDownloadOut(BaseModel):
    download_url: str  # signed GCS URL, valid for limited time
