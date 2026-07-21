"""
Researcher-adjustable thresholds — silence, suggestion confidence, rejection
count for retraining. Single-row config table (see app.models.system_config).
"""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.models.user import User
from app.schemas.system_config import SystemConfigOut, SystemConfigUpdate
from app.auth import require_researcher
from app.services.system_config import get_system_config

router = APIRouter(prefix="/config", tags=["config"])


@router.get("/", response_model=SystemConfigOut)
async def get_config(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_researcher),
):
    config = await get_system_config(db)
    return SystemConfigOut.model_validate(config)


@router.patch("/", response_model=SystemConfigOut)
async def update_config(
    body: SystemConfigUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_researcher),
):
    config = await get_system_config(db)

    updates = body.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(config, field, value)

    if updates:
        config.updated_by = current_user.id

    await db.commit()
    await db.refresh(config)
    return SystemConfigOut.model_validate(config)
