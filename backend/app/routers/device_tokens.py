# Programmer Name : Brenna Lo
# Program Name : device_tokens.py
# Description : Device token API endpoints for managing FCM tokens
# First Written on : 2024-06-10
# Edited on : 2024-07-18

"""
Registers a Flutter client's FCM token against the current user, so background
workers can push to them when a task finishes (segmentation, export, retrain,
consensus resolution) — no polling, no manual refresh needed on the client.
"""
from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.user import User
from app.models.device_token import DeviceToken
from app.schemas.device_token import DeviceTokenRegister, DeviceTokenUnregister
from app.auth import get_current_user
import uuid

router = APIRouter(prefix="/device-tokens", tags=["device-tokens"])


@router.post("/", status_code=status.HTTP_204_NO_CONTENT)
async def register_device_token(
    body: DeviceTokenRegister,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Call this on login and on app start (token can rotate). Upserts —
    if the token already exists (possibly for a different user, e.g. shared
    device where someone else logged out), it's reassigned to the caller."""
    result = await db.execute(select(DeviceToken).where(DeviceToken.token == body.token))
    existing = result.scalar_one_or_none()

    if existing:
        existing.user_id = current_user.id
        existing.platform = body.platform
    else:
        db.add(DeviceToken(
            id=uuid.uuid4(),
            user_id=current_user.id,
            token=body.token,
            platform=body.platform,
        ))

    await db.commit()


@router.delete("/", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_device_token(
    body: DeviceTokenUnregister,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Call this on logout so a shared/reset device stops receiving pushes
    meant for this user."""
    result = await db.execute(
        select(DeviceToken).where(
            DeviceToken.token == body.token,
            DeviceToken.user_id == current_user.id,
        )
    )
    existing = result.scalar_one_or_none()
    if existing:
        await db.delete(existing)
        await db.commit()
