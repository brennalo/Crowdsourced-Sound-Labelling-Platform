import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class SuggestionReview(Base):
    __tablename__ = "suggestion_reviews"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    segment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("segments.id"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    annotation_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("annotations.id"), nullable=False)
    decision: Mapped[str] = mapped_column(String, nullable=False)  # accepted | rejected
    reviewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    segment: Mapped["Segment"] = relationship(back_populates="suggestion_reviews")
    user: Mapped["User"] = relationship(back_populates="suggestion_reviews")
    annotation: Mapped["Annotation"] = relationship(back_populates="suggestion_reviews")
