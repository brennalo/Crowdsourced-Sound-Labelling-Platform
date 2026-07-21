# Programmer Name : Brenna Lo
# Program Name : record_screen.dart
# Description : UI and stateful widget of record screen tab for contributor
# First Written on : 2024-06-10
# Edited on : 2024-07-18

"""
augment.py — audio augmentation utilities.

Used in two places:
  1. backend/app/services/export.py — augments data at export time
  2. training/dataset.py — optional online augmentation during training

Keeping techniques mild to avoid shifting the distribution too far
from real forest recordings.
"""

import numpy as np
import librosa
from typing import Callable


def time_stretch_slow(audio: np.ndarray, rate: float = 0.9) -> np.ndarray:
    """Slow down audio by rate factor. <1.0 = slower."""
    return librosa.effects.time_stretch(audio, rate=rate)


def time_stretch_fast(audio: np.ndarray, rate: float = 1.1) -> np.ndarray:
    """Speed up audio by rate factor. >1.0 = faster."""
    return librosa.effects.time_stretch(audio, rate=rate)


def pitch_shift_up(audio: np.ndarray, sample_rate: int, n_steps: float = 2.0) -> np.ndarray:
    """Shift pitch up by n_steps semitones."""
    return librosa.effects.pitch_shift(audio, sr=sample_rate, n_steps=n_steps)


def pitch_shift_down(audio: np.ndarray, sample_rate: int, n_steps: float = 2.0) -> np.ndarray:
    """Shift pitch down by n_steps semitones."""
    return librosa.effects.pitch_shift(audio, sr=sample_rate, n_steps=-n_steps)


def add_gaussian_noise(audio: np.ndarray, snr_db: float = 20.0) -> np.ndarray:
    """
    Add Gaussian noise at a given SNR (dB).
    Higher SNR = cleaner signal = less noise.
    """
    signal_power = np.mean(audio ** 2)
    if signal_power == 0:
        return audio
    noise_power = signal_power / (10 ** (snr_db / 10))
    noise = np.random.normal(0, np.sqrt(noise_power), len(audio))
    return (audio + noise).astype(np.float32)


def random_gain(audio: np.ndarray, min_db: float = -6.0, max_db: float = 6.0) -> np.ndarray:
    """Apply random gain within a dB range."""
    gain_db = np.random.uniform(min_db, max_db)
    gain_linear = 10 ** (gain_db / 20)
    return np.clip(audio * gain_linear, -1.0, 1.0).astype(np.float32)


def get_all_augmentations(sample_rate: int) -> list[tuple[str, Callable]]:
    """
    Returns list of (name, function) pairs for all augmentation variants.
    Each function takes a numpy audio array and returns augmented array.
    """
    return [
        ("stretch_slow",  lambda a: time_stretch_slow(a, rate=0.9)),
        ("stretch_fast",  lambda a: time_stretch_fast(a, rate=1.1)),
        ("pitch_up",      lambda a: pitch_shift_up(a, sample_rate, n_steps=2.0)),
        ("pitch_down",    lambda a: pitch_shift_down(a, sample_rate, n_steps=2.0)),
        ("noise_20db",    lambda a: add_gaussian_noise(a, snr_db=20.0)),
    ]


def pad_or_trim(audio: np.ndarray, target_samples: int) -> np.ndarray:
    """Ensure audio is exactly target_samples long after augmentation."""
    if len(audio) >= target_samples:
        return audio[:target_samples]
    return np.pad(audio, (0, target_samples - len(audio)))
