# Programmer Name : Brenna Lo
# Program Name : device_token.py
# Description : Model class for device tokens in the database
# First Written on : 2024-06-10
# Edited on : 2024-07-18

import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, func, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class DeviceToken(Base):
    """
    FCM registration token for a user's device. A user can have several
    (multiple devices, or a reinstalled app) — token is the natural unique key
    since FCM issues a new one for the same device once the old one is stale.
    """
    __tablename__ = "device_tokens"
    __table_args__ = (UniqueConstraint("token", name="uq_device_tokens_token"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    token: Mapped[str] = mapped_column(String, nullable=False)
    platform: Mapped[str | None] = mapped_column(String, nullable=True)  # android | ios
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    user: Mapped["User"] = relationship()
