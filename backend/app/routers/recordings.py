from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.user import User
from app.models.recording import Recording
from app.schemas.recording import RecordingOut
from app.auth import get_current_user
from app.services.audio import upload_raw_audio_to_gcs
from app.workers.segmentation import run_segmentation
from datetime import datetime, timezone
import uuid

router = APIRouter(prefix="/recordings", tags=["recordings"])

ALLOWED_MIME_TYPES = {"audio/wav", "audio/x-wav", "audio/mpeg", "audio/mp4", "audio/ogg", "audio/flac"}


@router.post("/", response_model=RecordingOut, status_code=status.HTTP_201_CREATED)
async def upload_recording(
    file: UploadFile = File(...),
    recorded_at: datetime | None = None,
    location_lat: float | None = None,
    location_lng: float | None = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if file.content_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(status_code=400, detail=f"Unsupported audio format: {file.content_type}")

    audio_bytes = await file.read()
    if len(audio_bytes) == 0:
        raise HTTPException(status_code=400, detail="Empty file")

    recording_id = uuid.uuid4()
    gcs_path = await upload_raw_audio_to_gcs(
        audio_bytes=audio_bytes,
        recording_id=recording_id,
        filename=file.filename or "recording.wav",
    )

    recording = Recording(
        id=recording_id,
        user_id=current_user.id,
        gcs_raw_path=gcs_path,
        recorded_at=recorded_at or datetime.now(timezone.utc),
        location_lat=location_lat,
        location_lng=location_lng,
        status="processing",
    )
    db.add(recording)
    await db.commit()
    await db.refresh(recording)

    # Dispatch segmentation to Celery
    run_segmentation.delay(str(recording_id), gcs_path, str(current_user.id))

    return RecordingOut.model_validate(recording)


@router.get("/", response_model=list[RecordingOut])
async def list_my_recordings(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Recording)
        .where(Recording.user_id == current_user.id)
        .order_by(Recording.created_at.desc())
    )
    return [RecordingOut.model_validate(r) for r in result.scalars().all()]


@router.get("/{recording_id}", response_model=RecordingOut)
async def get_recording(
    recording_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Recording).where(Recording.id == recording_id, Recording.user_id == current_user.id)
    )
    recording = result.scalar_one_or_none()
    if not recording:
        raise HTTPException(status_code=404, detail="Recording not found")
    return RecordingOut.model_validate(recording)
