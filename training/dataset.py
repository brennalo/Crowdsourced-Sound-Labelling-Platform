"""
Dataset classes for both:
1. Frugalai HuggingFace dataset (initial training)
2. GCS-hosted crowdsourced segments (retraining)

Both produce (mel_spectrogram_tensor, label_idx) pairs.
"""

import io
import numpy as np
import librosa
import torch
from torch.utils.data import Dataset
from typing import Callable
from config import get_training_settings

settings = get_training_settings()

LABEL_TO_IDX = {label: idx for idx, label in enumerate(settings.labels)}


def audio_to_mel_tensor(audio: np.ndarray, sample_rate: int) -> torch.Tensor:
    """
    Convert raw audio array → mel spectrogram → normalised float tensor.
    Output shape: (1, n_mels, time_frames)
    """
    mel = librosa.feature.melspectrogram(
        y=audio,
        sr=sample_rate,
        n_mels=settings.n_mels,
        n_fft=settings.n_fft,
        hop_length=settings.hop_length,
    )
    mel_db = librosa.power_to_db(mel, ref=np.max)

    # Normalise to [0, 1]
    mel_min, mel_max = mel_db.min(), mel_db.max()
    if mel_max - mel_min > 0:
        mel_db = (mel_db - mel_min) / (mel_max - mel_min)

    return torch.tensor(mel_db, dtype=torch.float32).unsqueeze(0)  # (1, n_mels, T)


def load_audio_bytes(audio_bytes: bytes) -> tuple[np.ndarray, int]:
    buffer = io.BytesIO(audio_bytes)
    audio, sr = librosa.load(buffer, sr=settings.sample_rate, mono=True)
    return audio, sr


def pad_or_trim(audio: np.ndarray, target_samples: int) -> np.ndarray:
    """Ensure all clips are exactly target_samples long."""
    if len(audio) >= target_samples:
        return audio[:target_samples]
    return np.pad(audio, (0, target_samples - len(audio)))


TARGET_SAMPLES = int(settings.segment_length_sec * settings.sample_rate)


import random

class FrugalAIDataset(Dataset):
    def __init__(
        self,
        hf_dataset,
        label_map: dict[str, str] | None = None,
        transform: Callable | None = None,
        max_per_class: int | None = None,
        seed: int = 42,
    ):
        self.dataset = hf_dataset
        from datasets import Audio
        self.dataset = self.dataset.cast_column('audio', Audio(decode=False))
        self.label_map = label_map or {}
        self.transform = transform
        self.max_per_class = max_per_class
        self.seed = seed
        self._valid_indices = self._filter_valid()

    def _filter_valid(self) -> list[int]:
        # Group indices by resolved label instead of a flat valid list
        by_label: dict[str, list[int]] = {label: [] for label in LABEL_TO_IDX}
        for i, sample in enumerate(self.dataset):
            raw_label = str(sample.get("label", "")).lower()
            mapped = self.label_map.get(raw_label, raw_label)
            if mapped in LABEL_TO_IDX:
                by_label[mapped].append(i)

        total_available = sum(len(v) for v in by_label.values())

        if self.max_per_class is not None:
            rng = random.Random(self.seed)
            capped = []
            for label, indices in by_label.items():
                rng.shuffle(indices)
                take = indices[: self.max_per_class]
                capped.extend(take)
                print(f"[FrugalAIDataset] {label}: {len(take)}/{len(indices)} sampled")
            rng.shuffle(capped)  # avoid label-sorted ordering feeding into batches
            valid = capped
        else:
            valid = [i for indices in by_label.values() for i in indices]

        print(f"[FrugalAIDataset] {len(valid)}/{total_available} samples with valid labels"
              + (f" (capped at {self.max_per_class}/class)" if self.max_per_class else ""))
        return valid

    def __len__(self) -> int:
        return len(self._valid_indices)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, int]:
        sample = self.dataset[self._valid_indices[idx]]
        audio_data = sample['audio']

        if isinstance(audio_data, dict):
            if 'bytes' in audio_data and audio_data['bytes'] is not None:
                import io
                audio, sr = librosa.load(io.BytesIO(audio_data['bytes']), sr=settings.sample_rate, mono=True)
            elif 'array' in audio_data and audio_data['array'] is not None:
                audio = np.array(audio_data['array'], dtype=np.float32)
                sr = audio_data.get('sampling_rate', settings.sample_rate)
                if sr != settings.sample_rate:
                    audio = librosa.resample(audio, orig_sr=sr, target_sr=settings.sample_rate)
            else:
                raise ValueError(f'No usable audio. Keys: {list(audio_data.keys())}')
        else:
            import io
            audio, sr = librosa.load(io.BytesIO(audio_data), sr=settings.sample_rate, mono=True)

        raw_label = str(sample.get("label", "")).lower()
        mapped_label = self.label_map.get(raw_label, raw_label)
        label_idx = LABEL_TO_IDX[mapped_label]

        audio = pad_or_trim(audio, TARGET_SAMPLES)
        return audio_to_mel_tensor(audio, settings.sample_rate), label_idx

class GCSSegmentDataset(Dataset):
    """
    Dataset for crowdsourced segments stored in GCS.
    Takes a list of dicts: [{"gcs_path": str, "label": str}, ...]
    Downloads on demand — suitable for retraining on Cloud Run Job.
    """

    def __init__(self, records: list[dict], transform: Callable | None = None):
        self.records = records
        self.transform = transform
        self._bucket = None

    def _get_bucket(self):
        if self._bucket is None:
            from google.cloud import storage
            client = storage.Client()
            self._bucket = client.bucket(settings.gcs_bucket_name)
        return self._bucket

    def __len__(self) -> int:
        return len(self.records)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, int]:
        record = self.records[idx]
        gcs_path = record["gcs_path"]
        label_str = record["label"]

        blob = self._get_bucket().blob(gcs_path)
        audio_bytes = blob.download_as_bytes()
        audio, sr = load_audio_bytes(audio_bytes)
        audio = pad_or_trim(audio, TARGET_SAMPLES)

        if self.transform:
            audio = self.transform(audio)

        mel = audio_to_mel_tensor(audio, settings.sample_rate)
        label_idx = LABEL_TO_IDX[label_str]

        return mel, label_idx


class CombinedDataset(Dataset):
    """
    Concatenates FrugalAIDataset + GCSSegmentDataset for retraining.
    Frugalai provides base coverage; GCS adds crowdsourced data.
    """

    def __init__(self, datasets: list[Dataset]):
        self.datasets = datasets
        self.lengths = [len(d) for d in datasets]
        self.cumulative = []
        total = 0
        for l in self.lengths:
            total += l
            self.cumulative.append(total)

    def __len__(self) -> int:
        return self.cumulative[-1]

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, int]:
        for i, cum in enumerate(self.cumulative):
            if idx < cum:
                offset = idx - (self.cumulative[i - 1] if i > 0 else 0)
                return self.datasets[i][offset]
        raise IndexError(idx)
    

class PrecomputedDataset(Dataset):
    """
    Wraps any (mel_tensor, label) dataset and computes+caches every item
    once in memory, up front. Since audio_to_mel_tensor is deterministic
    (augmentation happens separately at export time, not during training),
    each sample only needs to be decoded and mel-transformed once instead
    of once per epoch. Also collapses GCSSegmentDataset's per-epoch GCS
    downloads down to a single download per sample.
    """

    def __init__(self, base_dataset: Dataset, desc: str = "dataset"):
        n = len(base_dataset)
        print(f"[PrecomputedDataset] Precomputing {n} items for {desc}...")
        self._items: list[tuple[torch.Tensor, int]] = []
        for i in range(n):
            mel, label = base_dataset[i]
            self._items.append((mel, label))
            if (i + 1) % 1000 == 0 or (i + 1) == n:
                print(f"[PrecomputedDataset] {i + 1}/{n} done")
        print(f"[PrecomputedDataset] Cached {n} items in memory for {desc}")

    def __len__(self) -> int:
        return len(self._items)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, int]:
        return self._items[idx]
