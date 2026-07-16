"""
Minimal standalone models for the training container's own DB reads/writes.
Intentionally NOT importing from backend/ — the training container's Docker
build context (training/) doesn't include that directory, so any cross-directory
import here fails at runtime with ModuleNotFoundError.
Keep these in sync manually if the corresponding backend tables' schemas change.
"""
import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, Text, Boolean
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID


class Base(DeclarativeBase):
    pass


class RetrainingJob(Base):
    __tablename__ = "retraining_jobs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    status: Mapped[str] = mapped_column(String, nullable=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    model_version_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    error_log: Mapped[str | None] = mapped_column(Text)


class Segment(Base):
    __tablename__ = "segments"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    gcs_path: Mapped[str] = mapped_column(String, nullable=False)
    review_status: Mapped[str] = mapped_column(String, nullable=False)
    effective_label: Mapped[str | None] = mapped_column(String)
    is_silent: Mapped[bool] = mapped_column(Boolean, nullable=False)