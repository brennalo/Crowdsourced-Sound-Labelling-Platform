import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class ResearcherReview(Base):
    __tablename__ = "researcher_reviews"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    segment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("segments.id"), nullable=False)
    researcher_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    # confirmed = label is correct | corrected = label was wrong, corrected_label set
    action: Mapped[str] = mapped_column(String, nullable=False)
    corrected_label: Mapped[str | None] = mapped_column(String, nullable=True)
    reviewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    segment: Mapped["Segment"] = relationship(back_populates="researcher_reviews")
    researcher: Mapped["User"] = relationship(back_populates="researcher_reviews")
