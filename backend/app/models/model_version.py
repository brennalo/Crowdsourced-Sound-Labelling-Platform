# Programmer Name : Brenna Lo
# Program Name : model_version.py
# Description : Model class for model versions in the database
# First Written on : 2024-06-10
# Edited on : 2024-07-18

import uuid
from datetime import datetime
from sqlalchemy import String, Float, Integer, Boolean, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class ModelVersion(Base):
    __tablename__ = "model_versions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    version_tag: Mapped[str] = mapped_column(String, nullable=False)  # e.g. v1.0, v1.1
    gcs_model_path: Mapped[str] = mapped_column(String, nullable=False)  # path to .onnx in GCS
    trigger_reason: Mapped[str] = mapped_column(String, nullable=False)  # manual | active_learning
    training_samples: Mapped[int | None] = mapped_column(Integer, nullable=True)
    accuracy: Mapped[float | None] = mapped_column(Float, nullable=True)  # validation accuracy
    is_active: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    retraining_jobs: Mapped[list["RetrainingJob"]] = relationship(back_populates="model_version")
