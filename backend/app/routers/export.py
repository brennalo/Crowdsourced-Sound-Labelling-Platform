from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.user import User
from app.models.export_job import ExportJob
from app.schemas.export import ExportJobOut, ExportDownloadOut
from app.auth import get_current_user, require_admin
from app.services.audio import generate_signed_url
from app.workers.export import run_export_job
import uuid

router = APIRouter(prefix="/exports", tags=["exports"])


@router.post("/", response_model=ExportJobOut, status_code=201)
async def request_export(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Admin only — triggers augmentation + zip export of all annotated data."""
    job = ExportJob(
        id=uuid.uuid4(),
        requested_by=current_user.id,
        status="queued",
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    run_export_job.delay(str(job.id))
    return ExportJobOut.model_validate(job)


@router.get("/{job_id}", response_model=ExportJobOut)
async def get_export_status(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    result = await db.execute(select(ExportJob).where(ExportJob.id == job_id))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Export job not found")
    return ExportJobOut.model_validate(job)


@router.get("/{job_id}/download", response_model=ExportDownloadOut)
async def get_export_download_url(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    result = await db.execute(select(ExportJob).where(ExportJob.id == job_id))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Export job not found")
    if job.status != "done":
        raise HTTPException(status_code=400, detail=f"Export not ready yet — status: {job.status}")
    if not job.gcs_export_path:
        raise HTTPException(status_code=500, detail="Export path missing")

    url = generate_signed_url(job.gcs_export_path, expiration_seconds=3600 * 24)
    return ExportDownloadOut(download_url=url)
