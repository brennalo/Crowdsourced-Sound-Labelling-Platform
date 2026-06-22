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
    # pending | annotated | rejected_suggestion | accepted_suggestion
    review_status: Mapped[str] = mapped_column(String, default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    recording: Mapped["Recording"] = relationship(back_populates="segments")
    annotations: Mapped[list["Annotation"]] = relationship(back_populates="segment")
    suggestion_reviews: Mapped[list["SuggestionReview"]] = relationship(back_populates="segment")
