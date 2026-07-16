import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class LabelChange(Base):
    """
    Unified audit log for every effective_label change on a segment.
    Replaces the old suggestion_reviews / researcher_reviews / annotations tables.

    change_source values:
        contributor_reject     - contributor rejected a model suggestion and corrected it
        consensus_flip         - 3-vote consensus disagreement flipped the label
        researcher_correction  - researcher directly overrode the label
        researcher_confirm     - researcher reviewed and confirmed the existing label (no change)
    """
    __tablename__ = "label_changes"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    segment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("segments.id"), nullable=False, index=True)
    changed_by_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=True
    )
    change_source: Mapped[str] = mapped_column(String, nullable=False)
    old_label: Mapped[str | None] = mapped_column(String, nullable=True)
    new_label: Mapped[str | None] = mapped_column(String, nullable=True)
    changed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)

    segment: Mapped["Segment"] = relationship(back_populates="label_changes")
    changed_by: Mapped["User | None"] = relationship(back_populates="label_changes")