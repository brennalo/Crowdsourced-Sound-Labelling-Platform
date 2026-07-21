# Programmer Name : Brenna Lo
# Program Name : retraining_job.py
# Description : Model class for retraining jobs in the database
# First Written on : 2024-06-10
# Edited on : 2024-07-18

import uuid
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, ForeignKey, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class RetrainingJob(Base):
    __tablename__ = "retraining_jobs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    triggered_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    triggered_by: Mapped[str] = mapped_column(String, nullable=False)  # rejection_threshold | manual
    status: Mapped[str] = mapped_column(String, default="queued")  # queued | running | done | failed
    rejection_count: Mapped[int | None] = mapped_column(Integer, nullable=True)  # snapshot at trigger
    model_version_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("model_versions.id"), nullable=True
    )
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    error_log: Mapped[str | None] = mapped_column(Text, nullable=True)

    model_version: Mapped["ModelVersion | None"] = relationship(back_populates="retraining_jobs")
