# Programmer Name : Brenna Lo
# Program Name : user.py
# Description : Model class for users in the database
# First Written on : 2024-06-10
# Edited on : 2024-07-18

import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String, nullable=False)
    display_name: Mapped[str | None] = mapped_column(String, nullable=True)
    role: Mapped[str] = mapped_column(String, default="contributor")  # contributor | researcher | admin
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    deactivated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    recordings: Mapped[list["Recording"]] = relationship(back_populates="user")
    consensus_votes: Mapped[list["ConsensusVote"]] = relationship(back_populates="voter")
    label_changes: Mapped[list["LabelChange"]] = relationship(back_populates="changed_by")
    export_jobs: Mapped[list["ExportJob"]] = relationship(back_populates="requested_by_user")