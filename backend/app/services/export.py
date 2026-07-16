import io
import csv
import uuid
import zipfile
import numpy as np
import librosa
import soundfile as sf
from app.services.audio import download_audio_from_gcs, upload_segment_to_gcs, get_bucket
from app.config import get_settings

settings = get_settings()


def augment_audio(audio: np.ndarray, sample_rate: int) -> list[tuple[str, np.ndarray]]:
    """
    Apply all augmentation techniques to a single audio clip.
    Returns list of (augmentation_name, augmented_audio) tuples.
    Delegates to training/augment.py for shared logic.
    """
    import sys, os
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../training"))
    try:
        from augment import get_all_augmentations, pad_or_trim
        target_samples = len(audio)
        augmentations = get_all_augmentations(sample_rate)
        results = []
        for name, fn in augmentations:
            aug = fn(audio)
            aug = pad_or_trim(aug, target_samples)
            results.append((name, aug))
        return results
    except ImportError:
        # Fallback if training module not on path (production API container)
        augmented = []
        augmented.append(("stretch_slow", librosa.effects.time_stretch(audio, rate=0.9)))
        augmented.append(("stretch_fast", librosa.effects.time_stretch(audio, rate=1.1)))
        augmented.append(("pitch_up", librosa.effects.pitch_shift(audio, sr=sample_rate, n_steps=2)))
        augmented.append(("pitch_down", librosa.effects.pitch_shift(audio, sr=sample_rate, n_steps=-2)))
        noise = (audio + 0.005 * np.random.randn(len(audio))).astype(np.float32)
        augmented.append(("noise", noise))
        return augmented


def audio_array_to_bytes(audio: np.ndarray, sample_rate: int) -> bytes:
    buffer = io.BytesIO()
    sf.write(buffer, audio, sample_rate, format="WAV", subtype="PCM_16")
    return buffer.getvalue()


def build_export_zip(
    annotated_segments: list[dict],
    job_id: uuid.UUID,
) -> str:
    """
    Downloads all annotated segments from GCS, applies augmentation,
    packages into a zip with a labels.csv, uploads zip to GCS.

    annotated_segments: list of {"segment_id", "gcs_path", "label"}
    Returns GCS path of the zip.
    """
    zip_buffer = io.BytesIO()
    csv_rows = []  # [filename, label]

    with zipfile.ZipFile(zip_buffer, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
        for entry in annotated_segments:
            segment_id = entry["segment_id"]
            gcs_path = entry["gcs_path"]
            label = entry["label"]

            try:
                audio, sr = download_audio_from_gcs(gcs_path)
            except Exception as e:
                print(f"[export] Skipping {gcs_path}: {e}")
                continue

            # Original
            original_filename = f"{label}/{segment_id}_original.wav"
            zf.writestr(original_filename, audio_array_to_bytes(audio, sr))
            csv_rows.append([original_filename, label])

            # Augmented variants
            for aug_name, aug_audio in augment_audio(audio, sr):
                aug_filename = f"{label}/{segment_id}_{aug_name}.wav"
                zf.writestr(aug_filename, audio_array_to_bytes(aug_audio, sr))
                csv_rows.append([aug_filename, label])

        # Write labels CSV
        csv_buffer = io.StringIO()
        writer = csv.writer(csv_buffer)
        writer.writerow(["file_name", "label"])
        writer.writerows(csv_rows)
        zf.writestr("metadata.csv", csv_buffer.getvalue())

    zip_buffer.seek(0)
    gcs_zip_path = f"exports/{job_id}/dataset.zip"
    blob = get_bucket().blob(gcs_zip_path)
    blob.upload_from_file(zip_buffer, content_type="application/zip")

    return gcs_zip_path
