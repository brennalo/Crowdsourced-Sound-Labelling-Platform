"""
seed_frugalai.py

One-time utility to inspect the rfcx/frugalai dataset before training.
Run this locally or in Colab to:
  1. Check what label column names the dataset uses
  2. Verify audio column structure
  3. Print class distribution
  4. Optionally upload a small sample to GCS for manual listening

Usage:
  python scripts/seed_frugalai.py
  python scripts/seed_frugalai.py --upload-sample --bucket your-bucket-name
"""

import argparse
from collections import Counter


def inspect_dataset():
    from datasets import load_dataset

    print("[seed] Loading rfcx/frugalai from HuggingFace (~3.78GB, may take a while)...")
    hf = load_dataset("rfcx/frugalai", trust_remote_code=True)

    print(f"\n[seed] Available splits: {list(hf.keys())}")

    for split_name, split in hf.items():
        print(f"\n── Split: {split_name} ({len(split)} samples) ──")
        print(f"  Columns: {split.column_names}")
        print(f"  Features: {split.features}")

        # Sample first record to understand audio structure
        sample = split[0]
        print(f"\n  Sample record keys: {list(sample.keys())}")

        if "audio" in sample:
            audio_info = sample["audio"]
            print(f"  Audio keys: {list(audio_info.keys()) if isinstance(audio_info, dict) else type(audio_info)}")
            if isinstance(audio_info, dict):
                print(f"  Audio array shape: {len(audio_info.get('array', []))}")
                print(f"  Sampling rate: {audio_info.get('sampling_rate')}")

        # Label distribution
        label_col = None
        for col in ["label", "labels", "class", "category"]:
            if col in split.column_names:
                label_col = col
                break

        if label_col:
            labels = [str(s[label_col]).lower() for s in split]
            dist = Counter(labels)
            print(f"\n  Label column: '{label_col}'")
            print(f"  Distribution:")
            for label, count in sorted(dist.items()):
                print(f"    {label}: {count} ({count/len(split)*100:.1f}%)")
        else:
            print(f"\n  No label column found — check column names above")


def upload_sample_to_gcs(bucket_name: str, n_samples: int = 5):
    """Upload a few samples to GCS for manual listening."""
    from datasets import load_dataset
    from google.cloud import storage
    import io
    import soundfile as sf
    import numpy as np

    hf = load_dataset("rfcx/frugalai", trust_remote_code=True)
    split = list(hf.values())[0]

    client = storage.Client()
    bucket = client.bucket(bucket_name)

    print(f"\n[seed] Uploading {n_samples} sample clips to gs://{bucket_name}/sample_clips/")

    for i in range(min(n_samples, len(split))):
        sample = split[i]
        audio_data = sample["audio"]
        audio = np.array(audio_data["array"], dtype=np.float32)
        sr = audio_data["sampling_rate"]
        label = str(sample.get("label", "unknown")).lower()

        buf = io.BytesIO()
        sf.write(buf, audio, sr, format="WAV")
        buf.seek(0)

        gcs_path = f"sample_clips/{i:03d}_{label}.wav"
        blob = bucket.blob(gcs_path)
        blob.upload_from_file(buf, content_type="audio/wav")
        print(f"  Uploaded: {gcs_path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--upload-sample", action="store_true", help="Upload sample clips to GCS")
    parser.add_argument("--bucket", default="", help="GCS bucket name (required with --upload-sample)")
    parser.add_argument("--n-samples", type=int, default=5)
    args = parser.parse_args()

    inspect_dataset()

    if args.upload_sample:
        if not args.bucket:
            print("\n[seed] --bucket required for --upload-sample")
            return
        upload_sample_to_gcs(args.bucket, args.n_samples)

    print("\n[seed] Done. Use the label names above to update label_map in dataset.py if needed.")


if __name__ == "__main__":
    main()
