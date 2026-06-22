import uuid
from app.workers.celery_app import celery_app
from app.config import get_settings

settings = get_settings()


@celery_app.task(bind=True, max_retries=3, default_retry_delay=10)
def run_segmentation(self, recording_id: str, gcs_raw_path: str, user_id: str):
    """
    Downloads raw recording from GCS, splits into 3s segments,
    discards silent ones, uploads segments, updates DB.
    Runs synchronously inside Celery worker using a sync DB session.
    """
    import asyncio
    asyncio.run(_run_segmentation(recording_id, gcs_raw_path, user_id))


async def _run_segmentation(recording_id: str, gcs_raw_path: str, user_id: str):
    from sqlalchemy.ext.asyncio import AsyncSession
    from sqlalchemy import select
    from app.database import AsyncSessionLocal
    from app.models.recording import Recording
    from app.models.segment import Segment
    from app.services.audio import (
        download_audio_from_gcs,
        segment_audio,
        upload_segment_to_gcs,
        delete_from_gcs,
        is_silent,
    )

    recording_uuid = uuid.UUID(recording_id)
    user_uuid = uuid.UUID(user_id)

    async with AsyncSessionLocal() as db:
        try:
            # Load the raw audio
            audio, sr = download_audio_from_gcs(gcs_raw_path)

            segments = segment_audio(audio, sr, settings.segment_length_sec)
            segment_records = []

            for seg in segments:
                seg_id = uuid.uuid4()
                silent = is_silent(seg["audio"], settings.silence_threshold_dbfs)
                gcs_path = f"segments/{recording_id}/{seg_id}.wav"

                if silent:
                    # Create record with is_silent=True but don't upload audio
                    segment_records.append(Segment(
                        id=seg_id,
                        recording_id=recording_uuid,
                        user_id=user_uuid,
                        gcs_path=gcs_path,
                        start_sec=seg["start_sec"],
                        end_sec=seg["end_sec"],
                        is_silent=True,
                        review_status="pending",
                    ))
                else:
                    upload_segment_to_gcs(seg["audio"], sr, gcs_path)
                    segment_records.append(Segment(
                        id=seg_id,
                        recording_id=recording_uuid,
                        user_id=user_uuid,
                        gcs_path=gcs_path,
                        start_sec=seg["start_sec"],
                        end_sec=seg["end_sec"],
                        is_silent=False,
                        review_status="pending",
                    ))

            db.add_all(segment_records)

            # Update recording status
            result = await db.execute(select(Recording).where(Recording.id == recording_uuid))
            recording = result.scalar_one_or_none()
            if recording:
                import librosa
                recording.duration_sec = librosa.get_duration(y=audio, sr=sr)
                recording.status = "done"

            # Delete raw file from GCS after successful segmentation
            delete_from_gcs(gcs_raw_path)

            await db.commit()
            print(f"[segmentation] Recording {recording_id}: {len(segment_records)} segments created")

        except Exception as e:
            # Mark recording as failed
            result = await db.execute(select(Recording).where(Recording.id == recording_uuid))
            recording = result.scalar_one_or_none()
            if recording:
                recording.status = "failed"
                await db.commit()
            raise e
