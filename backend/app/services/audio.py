import io
import uuid
import numpy as np
import librosa
import soundfile as sf
from google.cloud import storage
from google.cloud.storage import Blob
from datetime import timedelta
from app.config import get_settings

settings = get_settings()
_gcs_client: storage.Client | None = None


def get_gcs_client() -> storage.Client:
    global _gcs_client
    if _gcs_client is None:
        _gcs_client = storage.Client()
    return _gcs_client


def get_bucket():
    return get_gcs_client().bucket(settings.gcs_bucket_name)


async def upload_raw_audio_to_gcs(
    audio_bytes: bytes,
    recording_id: uuid.UUID,
    filename: str,
) -> str:
    """Upload original recording to GCS. Returns GCS path (not URL)."""
    gcs_path = f"raw/{recording_id}/{filename}"
    blob: Blob = get_bucket().blob(gcs_path)
    blob.upload_from_string(audio_bytes, content_type="audio/wav")
    return gcs_path


def upload_segment_to_gcs(audio_array: np.ndarray, sample_rate: int, gcs_path: str) -> None:
    """Write a numpy audio array as WAV to GCS."""
    buffer = io.BytesIO()
    sf.write(buffer, audio_array, sample_rate, format="WAV", subtype="PCM_16")
    buffer.seek(0)
    blob: Blob = get_bucket().blob(gcs_path)
    blob.upload_from_file(buffer, content_type="audio/wav")


def download_audio_from_gcs(gcs_path: str) -> tuple[np.ndarray, int]:
    """Download WAV from GCS, return (audio_array, sample_rate)."""
    blob: Blob = get_bucket().blob(gcs_path)
    audio_bytes = blob.download_as_bytes()
    buffer = io.BytesIO(audio_bytes)
    audio, sr = librosa.load(buffer, sr=settings.sample_rate, mono=True)
    return audio, sr


def delete_from_gcs(gcs_path: str) -> None:
    blob: Blob = get_bucket().blob(gcs_path)
    blob.delete(if_generation_match=None)


def generate_signed_url(gcs_path: str, expiration_seconds: int = 3600) -> str:
    """Generate a signed URL for client-side audio playback."""
    blob: Blob = get_bucket().blob(gcs_path)
    return blob.generate_signed_url(
        expiration=timedelta(seconds=expiration_seconds),
        method="GET",
        version="v4",
    )


def is_silent(audio: np.ndarray, threshold_dbfs: float) -> bool:
    """Return True if RMS energy of clip is below threshold_dbfs."""
    rms = np.sqrt(np.mean(audio ** 2))
    if rms == 0:
        return True
    dbfs = 20 * np.log10(rms)
    return dbfs < threshold_dbfs


def segment_audio(
    audio: np.ndarray,
    sample_rate: int,
    segment_length_sec: float,
) -> list[dict]:
    """
    Split audio array into fixed-length segments.
    Returns list of dicts: {audio, start_sec, end_sec}
    Drops the last partial segment if shorter than segment_length_sec.
    """
    segment_samples = int(segment_length_sec * sample_rate)
    total_samples = len(audio)
    segments = []

    start = 0
    while start + segment_samples <= total_samples:
        end = start + segment_samples
        segments.append({
            "audio": audio[start:end],
            "start_sec": start / sample_rate,
            "end_sec": end / sample_rate,
        })
        start = end

    return segments
