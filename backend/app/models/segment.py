import uuid
from datetime import datetime
from sqlalchemy import String, Float, Boolean, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class Segment(Base):
    __tablename__ = "segments"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    recording_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("recordings.id"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    gcs_path: Mapped[str] = mapped_column(String, nullable=False)
    start_sec: Mapped[float] = mapped_column(Float, nullable=False)
    end_sec: Mapped[float] = mapped_column(Float, nullable=False)
    is_silent: Mapped[bool] = mapped_column(Boolean, default=False)

    # review_status values:
    #   annotation_pending  — low-confidence, contributor picks label
    #   suggestion_pending  — high-confidence, contributor accepts/rejects+corrects
    #   excluded_other      — labelled "other", re-labelable
    #   training_pool       — authoritative label set, used in training
    #   consensus_open      — disputed, voting in progress
    review_status: Mapped[str] = mapped_column(String, default="annotation_pending")

    # Authoritative label used by training export. Set when entering training_pool.
    effective_label: Mapped[str | None] = mapped_column(String, nullable=True)

    # Original model prediction — never changes after inference
    model_label: Mapped[str | None] = mapped_column(String, nullable=True)
    model_confidence: Mapped[float | None] = mapped_column(Float, nullable=True)

    # How segment entered training_pool: manual | accepted | auto_7day
    pool_entry_reason: Mapped[str | None] = mapped_column(String, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    recording: Mapped["Recording"] = relationship(back_populates="segments")
    consensus_votes: Mapped[list["ConsensusVote"]] = relationship(back_populates="segment")
    label_changes: Mapped[list["LabelChange"]] = relationship(back_populates="segment")