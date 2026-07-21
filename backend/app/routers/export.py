# Programmer Name : Brenna Lo
# Program Name : export.py
# Description : Export API endpoints for managing export jobs
# First Written on : 2024-06-10
# Edited on : 2024-07-18

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.user import User
from app.models.export_job import ExportJob
from app.schemas.export import ExportJobOut, ExportDownloadOut
from app.auth import require_researcher
from app.services.audio import generate_signed_url
from app.workers.export import run_export_job
import uuid

router = APIRouter(prefix="/exports", tags=["exports"])


@router.post("/", response_model=ExportJobOut, status_code=201)
async def request_export(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_researcher),
):
    job = ExportJob(id=uuid.uuid4(), requested_by=current_user.id, status="queued")
    db.add(job)
    await db.commit()
    await db.refresh(job)
    run_export_job.delay(str(job.id))
    return ExportJobOut.model_validate(job)


@router.get("/my", response_model=list[ExportJobOut])
async def list_my_exports(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_researcher),
):
    result = await db.execute(
        select(ExportJob)
        .where(ExportJob.requested_by == current_user.id)
        .order_by(ExportJob.requested_at.desc())
    )
    return [ExportJobOut.model_validate(j) for j in result.scalars().all()]


@router.get("/{job_id}", response_model=ExportJobOut)
async def get_export_status(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_researcher),
):
    result = await db.execute(
        select(ExportJob).where(ExportJob.id == job_id, ExportJob.requested_by == current_user.id)
    )
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Export job not found")
    return ExportJobOut.model_validate(job)


@router.get("/{job_id}/download", response_model=ExportDownloadOut)
async def get_download_url(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_researcher),
):
    result = await db.execute(
        select(ExportJob).where(ExportJob.id == job_id, ExportJob.requested_by == current_user.id)
    )
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Export job not found")
    if job.status != "done":
        raise HTTPException(status_code=400, detail=f"Export not ready — status: {job.status}")
    return ExportDownloadOut(download_url=generate_signed_url(job.gcs_export_path, expiration_seconds=86400))
