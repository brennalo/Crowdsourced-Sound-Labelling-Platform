import uuid
from datetime import datetime
from sqlalchemy import String, Float, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class Annotation(Base):
    __tablename__ = "annotations"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    segment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("segments.id"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    label: Mapped[str] = mapped_column(String, nullable=False)  # environment | chainsaw (extensible)
    source: Mapped[str] = mapped_column(String, nullable=False)  # manual | model
    confidence: Mapped[float | None] = mapped_column(Float, nullable=True)  # null if manual
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    segment: Mapped["Segment"] = relationship(back_populates="annotations")
    user: Mapped["User"] = relationship(back_populates="annotations")
    suggestion_reviews: Mapped[list["SuggestionReview"]] = relationship(back_populates="annotation")
