import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, func, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class ConsensusVote(Base):
    __tablename__ = "consensus_votes"
    __table_args__ = (UniqueConstraint("segment_id", "voter_id"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    segment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("segments.id"), nullable=False)
    voter_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    # agree = current effective_label is correct | disagree = it is wrong
    verdict: Mapped[str] = mapped_column(String, nullable=False)
    voted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    segment: Mapped["Segment"] = relationship(back_populates="consensus_votes")
    voter: Mapped["User"] = relationship(back_populates="consensus_votes")
