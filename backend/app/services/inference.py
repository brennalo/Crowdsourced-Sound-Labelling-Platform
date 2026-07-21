# Programmer Name : Brenna Lo
# Program Name : inference.py
# Description : Inference functionality for running predictions on audio segments as function helper class
# First Written on : 2024-06-10
# Edited on : 2024-07-18

import io
import os
import tempfile
import numpy as np
import librosa
import onnxruntime as ort
from google.cloud import storage
from app.config import get_settings
from app.services.audio import download_audio_from_gcs, get_bucket

settings = get_settings()

# Labels must match training order
LABELS = ["chainsaw", "environment"]

# Mel spectrogram config — must match training
N_MELS = 64
HOP_LENGTH = 512
N_FFT = 1024


def audio_to_mel(audio: np.ndarray, sample_rate: int) -> np.ndarray:
    """Convert audio array to mel spectrogram, normalised to [0, 1]."""
    mel = librosa.feature.melspectrogram(
        y=audio,
        sr=sample_rate,
        n_mels=N_MELS,
        n_fft=N_FFT,
        hop_length=HOP_LENGTH,
    )
    mel_db = librosa.power_to_db(mel, ref=np.max)
    # Normalise to [0, 1]
    mel_min, mel_max = mel_db.min(), mel_db.max()
    if mel_max - mel_min > 0:
        mel_db = (mel_db - mel_min) / (mel_max - mel_min)
    # Shape: (1, 1, n_mels, time) — batch, channel, height, width
    return mel_db[np.newaxis, np.newaxis, :, :].astype(np.float32)


class InferenceService:
    def __init__(self):
        self._session: ort.InferenceSession | None = None
        self._model_path: str | None = None

    def load_model(self, gcs_path: str) -> None:
        """Download ONNX model from GCS and load into onnxruntime."""
        blob = get_bucket().blob(gcs_path)
        tmp_dir = tempfile.mkdtemp()
        local_path = os.path.join(tmp_dir, "model.onnx")
        blob.download_to_filename(local_path)

        # If the model uses external data, the companion file must also be
        # downloaded and placed in the same directory with matching name.
        # Check bucket for a sibling blob (e.g. gcs_path + "_data" or ".data")
        # and download it here too if it exists.

        self._session = ort.InferenceSession(local_path, providers=["CPUExecutionProvider"])
        self._model_path = gcs_path
        print(f"[inference] Loaded model from {gcs_path}")

    def is_loaded(self) -> bool:
        return self._session is not None

    def predict(self, audio: np.ndarray, sample_rate: int) -> dict:
        """
        Run inference on audio array.
        Returns {"label": str, "confidence": float, "scores": list[float]}
        """
        if not self._session:
            raise RuntimeError("Model not loaded")

        mel = audio_to_mel(audio, sample_rate)
        input_name = self._session.get_inputs()[0].name
        outputs = self._session.run(None, {input_name: mel})

        # outputs[0] shape: (1, num_classes) — raw logits or softmax
        logits = outputs[0][0]
        # Apply softmax if not already applied
        exp = np.exp(logits - logits.max())
        probs = exp / exp.sum()

        predicted_idx = int(np.argmax(probs))
        confidence = float(probs[predicted_idx])

        return {
            "label": LABELS[predicted_idx],
            "confidence": confidence,
            "scores": probs.tolist(),
        }

    async def predict_from_gcs(self, gcs_path: str) -> dict | None:
        """Download segment from GCS and run prediction."""
        if not self._session:
            return None
        try:
            audio, sr = download_audio_from_gcs(gcs_path)
            return self.predict(audio, sr)
        except Exception as e:
            print(f"[inference] Error predicting {gcs_path}: {e}")
            return None

    def get_least_confident_threshold(self) -> float:
        """
        Confidence below this value flags segment for human review.
        Start at 0.75 — tune empirically after initial model training.
        """
        return 0.75


# Module-level singleton — shared across all requests in the same worker process
_inference_service = InferenceService()


def get_inference_service() -> InferenceService:
    return _inference_service


def load_active_model_from_gcs(gcs_path: str) -> None:
    """Called on FastAPI startup and after retraining completes."""
    _inference_service.load_model(gcs_path)
