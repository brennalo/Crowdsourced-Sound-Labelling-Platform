import uuid
from app.workers.celery_app import celery_app
from app.config import get_settings
import subprocess

settings = get_settings()


@celery_app.task(bind=True, max_retries=3, default_retry_delay=10)
def run_segmentation(self, recording_id: str, gcs_raw_path: str, user_id: str):
    import asyncio
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        loop.run_until_complete(_run_segmentation(recording_id, gcs_raw_path, user_id))
    finally:
        loop.close()


async def _run_segmentation(recording_id: str, gcs_raw_path: str, user_id: str):
    from sqlalchemy import select
    from app.database import AsyncSessionLocal
    from app.models.recording import Recording
    from app.models.segment import Segment
    from app.services.audio import (
        download_audio_from_gcs, segment_audio,
        upload_segment_to_gcs, delete_from_gcs, is_silent,
    )
    from app.services.inference import get_inference_service
    from app.services.system_config import get_system_config
    from app.services.push import send_push_to_user

    recording_uuid = uuid.UUID(recording_id)
    user_uuid = uuid.UUID(user_id)
    inference = get_inference_service()

    async with AsyncSessionLocal() as db:
        try:
            config = await get_system_config(db)

            audio, sr = download_audio_from_gcs(gcs_raw_path)
            raw_segments = segment_audio(audio, sr, settings.segment_length_sec)
            segment_records = []
            non_silent_idx = 0  # 1-based position among non-silent segments only —
            # matches what contributors actually see, since silent segments are
            # filtered out of every list view (is_silent == False)

            for seg in raw_segments:
                seg_id = uuid.uuid4()
                silent = is_silent(seg["audio"], config.silence_threshold_dbfs)
                gcs_path = f"segments/{recording_id}/{seg_id}.wav"

                if silent:
                    segment_records.append(Segment(
                        id=seg_id,
                        recording_id=recording_uuid,
                        user_id=user_uuid,
                        gcs_path=gcs_path,
                        start_sec=seg["start_sec"],
                        end_sec=seg["end_sec"],
                        is_silent=True,
                        review_status="annotation_pending",
                    ))
                    continue

                non_silent_idx += 1
                upload_segment_to_gcs(seg["audio"], sr, gcs_path)

                # Run inference immediately after upload
                model_label = None
                model_confidence = None
                review_status = "annotation_pending"

                if inference.is_loaded():
                    print ("inference is loaded, running prediction")
                    try:
                        prediction = inference.predict(seg["audio"], sr)
                        model_label = prediction["label"]
                        model_confidence = prediction["confidence"]
                        # Route by confidence threshold (researcher-adjustable)
                        if model_confidence >= config.confidence_threshold:
                            review_status = "suggestion_pending"
                        else:
                            review_status = "annotation_pending"
                    except Exception as e:
                        print(f"[segmentation] Inference failed for {seg_id}: {e}")

                segment_records.append(Segment(
                    id=seg_id,
                    recording_id=recording_uuid,
                    user_id=user_uuid,
                    gcs_path=gcs_path,
                    start_sec=seg["start_sec"],
                    end_sec=seg["end_sec"],
                    is_silent=False,
                    review_status=review_status,
                    model_label=model_label,
                    model_confidence=model_confidence,
                    sequence_num=non_silent_idx,
                ))

            db.add_all(segment_records)

            result = await db.execute(select(Recording).where(Recording.id == recording_uuid))
            recording = result.scalar_one_or_none()
            if recording:
                import librosa
                recording.duration_sec = librosa.get_duration(y=audio, sr=sr)
                recording.status = "done"
                recording.total_segments = non_silent_idx

            delete_from_gcs(gcs_raw_path)
            await db.commit()

            non_silent = sum(1 for s in segment_records if not s.is_silent)
            suggestion = sum(1 for s in segment_records if s.review_status == "suggestion_pending")
            annotation = sum(1 for s in segment_records if s.review_status == "annotation_pending" and not s.is_silent)
            print(
                f"[segmentation] {recording_id}: {non_silent} segments "
                f"({suggestion} suggestion_pending, {annotation} annotation_pending)"
            )

            # Notify the contributor's device(s) — data-only push, client
            # invalidates its recordings/segments providers on receipt.
            await send_push_to_user(
                db,
                user_id=user_uuid,
                data={
                    "type": "segmentation_done",
                    "recording_id": recording_id,
                    "segment_count": str(non_silent),
                },
                notification=(
                    {
                        "title": "Recording processed",
                        "body": f"{non_silent} clip{'s' if non_silent != 1 else ''} ready for review.",
                    }
                    if (suggestion + annotation) > 0
                    else None
                ),
            )

        except Exception as e:
            result = await db.execute(select(Recording).where(Recording.id == recording_uuid))
            recording = result.scalar_one_or_none()
            if recording:
                recording.status = "failed"
                await db.commit()
            raise e
