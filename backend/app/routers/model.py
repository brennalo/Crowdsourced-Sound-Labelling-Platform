# Programmer Name : Brenna Lo
# Program Name : model.py
# Description : Model API endpoints for managing model versions and retraining jobs
# First Written on : 2024-06-10
# Edited on : 2024-07-18

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from datetime import datetime
from app.database import get_db
from app.models.model_version import ModelVersion
from app.models.retraining_job import RetrainingJob
from app.auth import require_admin, require_researcher
import uuid

router = APIRouter(prefix="/model", tags=["model"])


class ModelVersionOut(BaseModel):
    id: uuid.UUID
    version_tag: str
    gcs_model_path: str
    trigger_reason: str
    training_samples: int | None
    accuracy: float | None
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class RetrainingJobOut(BaseModel):
    id: uuid.UUID
    triggered_at: datetime
    triggered_by: str
    status: str
    rejection_count: int | None
    completed_at: datetime | None
    error_log: str | None

    model_config = {"from_attributes": True}


@router.get("/active", response_model=ModelVersionOut)
async def get_active_model(
    db: AsyncSession = Depends(get_db),
    _: object = Depends(require_researcher),
):
    result = await db.execute(select(ModelVersion).where(ModelVersion.is_active == True))
    model = result.scalar_one_or_none()
    if not model:
        raise HTTPException(status_code=404, detail="No active model found")
    return ModelVersionOut.model_validate(model)


@router.get("/versions", response_model=list[ModelVersionOut])
async def list_model_versions(
    db: AsyncSession = Depends(get_db),
    _: object = Depends(require_researcher),
):
    result = await db.execute(select(ModelVersion).order_by(ModelVersion.created_at.desc()))
    return [ModelVersionOut.model_validate(m) for m in result.scalars().all()]


@router.get("/retraining-jobs", response_model=list[RetrainingJobOut])
async def list_retraining_jobs(
    db: AsyncSession = Depends(get_db),
    _: object = Depends(require_researcher),
):
    result = await db.execute(select(RetrainingJob).order_by(RetrainingJob.triggered_at.desc()).limit(20))
    return [RetrainingJobOut.model_validate(j) for j in result.scalars().all()]


@router.post("/trigger-retrain", response_model=RetrainingJobOut, status_code=201)
async def trigger_manual_retrain(
    db: AsyncSession = Depends(get_db),
    _: object = Depends(require_researcher),
):
    """Admin-only manual retrain trigger — bypasses rejection threshold."""
    # Prevent duplicate jobs
    in_progress = await db.execute(
        select(RetrainingJob).where(RetrainingJob.status.in_(["queued", "running"]))
    )
    if in_progress.scalar_one_or_none():
        from fastapi import HTTPException
        raise HTTPException(status_code=409, detail="A retraining job is already queued or running")

    job = RetrainingJob(
        id=uuid.uuid4(),
        triggered_by="manual",
        status="queued",
        rejection_count=None,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    from app.workers.retraining import trigger_retrain_job
    trigger_retrain_job.delay(str(job.id))

    return RetrainingJobOut.model_validate(job)
