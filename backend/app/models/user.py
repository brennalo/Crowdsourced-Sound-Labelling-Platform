import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String, nullable=False)
    display_name: Mapped[str | None] = mapped_column(String, nullable=True)
    role: Mapped[str] = mapped_column(String, default="contributor")  # contributor | admin
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    recordings: Mapped[list["Recording"]] = relationship(back_populates="user")
    annotations: Mapped[list["Annotation"]] = relationship(back_populates="user")
    suggestion_reviews: Mapped[list["SuggestionReview"]] = relationship(back_populates="user")
    export_jobs: Mapped[list["ExportJob"]] = relationship(back_populates="requested_by_user")
