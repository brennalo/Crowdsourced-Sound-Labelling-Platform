# Programmer Name : Brenna Lo
# Program Name : system_config.py
# Description : Model class for system configuration in the database
# First Written on : 2024-06-10
# Edited on : 2024-07-18

import uuid
from datetime import datetime
from sqlalchemy import Float, Integer, DateTime, ForeignKey, CheckConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class SystemConfig(Base):
    """
    Singleton row (id is always 1) holding researcher-adjustable tunables that
    previously lived only in backend/.env — silence threshold, suggestion
    confidence threshold, and the rejection count that triggers a retrain.

    Changing a row here takes effect on the *next* task run (segmentation,
    suggestion routing, rejection counting) — nothing is cached at process
    startup. It does NOT retroactively change segments already processed.
    """
    __tablename__ = "system_config"
    __table_args__ = (CheckConstraint("id = 1", name="system_config_singleton"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)

    silence_threshold_dbfs: Mapped[float] = mapped_column(Float, nullable=False, default=-40.0)
    confidence_threshold: Mapped[float] = mapped_column(Float, nullable=False, default=0.75)
    rejection_threshold: Mapped[int] = mapped_column(Integer, nullable=False, default=150)

    updated_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    updated_by_user: Mapped["User | None"] = relationship()
