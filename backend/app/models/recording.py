import uuid
from datetime import datetime
from sqlalchemy import String, Float, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class Recording(Base):
    __tablename__ = "recordings"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    gcs_raw_path: Mapped[str] = mapped_column(String, nullable=False)  # kept as audit ref even after deletion
    duration_sec: Mapped[float | None] = mapped_column(Float, nullable=True)
    recorded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    location_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    location_lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    status: Mapped[str] = mapped_column(String, default="processing")  # processing | done | failed
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    user: Mapped["User"] = relationship(back_populates="recordings")
    segments: Mapped[list["Segment"]] = relationship(back_populates="recording")
