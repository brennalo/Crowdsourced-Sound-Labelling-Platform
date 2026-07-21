# Programmer Name : Brenna Lo
# Program Name : export_onnx.py
# Description : Export trained PyTorch model to ONNX format and upload to GCS
# First Written on : 2024-06-10
# Edited on : 2024-07-18

"""
export_onnx.py

Converts trained PyTorch model → ONNX, uploads to GCS,
registers as new active model version in PostgreSQL.

Can be called:
  1. From train.py automatically after training
  2. Standalone after manual Colab training:
       python export_onnx.py --weights /path/to/best_weights.pt --tag v1.0
"""

import argparse
import asyncio
import io
import uuid
from datetime import datetime, timezone
from pathlib import Path

import torch
import numpy as np

from config import get_training_settings
from model import build_model

settings = get_training_settings()


def export_to_onnx(model: torch.nn.Module, output_path: Path) -> Path:
    """Export PyTorch model to ONNX format."""
    model.eval()

    # Dummy input matching inference input shape
    # (batch=1, channel=1, n_mels=64, time_frames=130)
    # time_frames = ceil(segment_samples / hop_length)
    segment_samples = int(settings.segment_length_sec * settings.sample_rate)
    time_frames = segment_samples // settings.hop_length + 1
    dummy_input = torch.randn(1, 1, settings.n_mels, time_frames)

    onnx_path = output_path / "model.onnx"

    torch.onnx.export(
        model,
        dummy_input,
        str(onnx_path),
        export_params=True,
        opset_version=17,
        do_constant_folding=True,
        input_names=["mel_spectrogram"],
        output_names=["logits"],
        dynamic_axes={
            "mel_spectrogram": {0: "batch_size", 3: "time_frames"},
            "logits": {0: "batch_size"},
        },
        dynamo=False,
    )
    print(f"[export] ONNX model saved to {onnx_path}")
    return onnx_path


def verify_onnx(onnx_path: Path):
    """Quick sanity check — run a forward pass with onnxruntime."""
    import onnxruntime as ort

    segment_samples = int(settings.segment_length_sec * settings.sample_rate)
    time_frames = segment_samples // settings.hop_length + 1
    dummy = np.random.randn(1, 1, settings.n_mels, time_frames).astype(np.float32)

    session = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    output = session.run(None, {input_name: dummy})

    assert output[0].shape == (1, settings.num_classes), f"Unexpected output shape: {output[0].shape}"
    print(f"[export] ONNX verification passed — output shape: {output[0].shape}")


def upload_to_gcs(onnx_path: Path, version_tag: str) -> str:
    """Upload ONNX file to GCS, return GCS path."""
    from google.cloud import storage

    gcs_path = f"{settings.model_gcs_prefix}{version_tag}/model.onnx"
    client = storage.Client()
    bucket = client.bucket(settings.gcs_bucket_name)
    blob = bucket.blob(gcs_path)
    blob.upload_from_filename(str(onnx_path), content_type="application/octet-stream")
    print(f"[export] Uploaded to GCS: {gcs_path}")
    return gcs_path


async def register_model_in_db(
    version_tag: str,
    gcs_model_path: str,
    val_accuracy: float,
    training_samples: int,
    trigger_reason: str,
    retraining_job_id: str | None,
) -> str:
    """
    Deactivates all existing models, inserts new model_version as active,
    updates retraining_job if provided.
    Returns new model version UUID.
    """
    from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
    from sqlalchemy import select, update
    import sys
    import os
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))
    from db_scheme_model_part import ModelVersion
    from db_scheme_model_part import RetrainingJob

    engine = create_async_engine(settings.database_url)
    Session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with Session() as db:
        # Deactivate all existing models
        await db.execute(update(ModelVersion).values(is_active=False))

        # Insert new active model
        new_version = ModelVersion(
            id=uuid.uuid4(),
            version_tag=version_tag,
            gcs_model_path=gcs_model_path,
            trigger_reason=trigger_reason,
            training_samples=training_samples,
            accuracy=val_accuracy,
            is_active=True,
        )
        db.add(new_version)
        await db.flush()

        # Update retraining job if this was triggered by active learning
        if retraining_job_id:
            result = await db.execute(
                select(RetrainingJob).where(RetrainingJob.id == retraining_job_id)
            )
            job = result.scalar_one_or_none()
            if job:
                job.status = "done"
                job.model_version_id = new_version.id
                job.completed_at = datetime.now(timezone.utc)

        await db.commit()
        model_id = str(new_version.id)

    await engine.dispose()
    print(f"[export] Registered model {version_tag} in DB (id={model_id})")
    return model_id


def generate_version_tag() -> str:
    """Generate version tag based on timestamp: v20240101_120000"""
    return f"v{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"


def export_and_register(
    model: torch.nn.Module,
    output_dir: Path,
    val_accuracy: float,
    training_samples: int,
    trigger_reason: str = "manual",
    retraining_job_id: str | None = None,
    version_tag: str | None = None,
):
    version_tag = version_tag or generate_version_tag()

    # 1. Export to ONNX
    onnx_path = export_to_onnx(model, output_dir)

    # 2. Verify
    verify_onnx(onnx_path)

    # 3. Upload to GCS
    gcs_path = upload_to_gcs(onnx_path, version_tag)

    # 4. Register in DB (if database_url is configured)
    if settings.database_url:
        asyncio.run(register_model_in_db(
            version_tag=version_tag,
            gcs_model_path=gcs_path,
            val_accuracy=val_accuracy,
            training_samples=training_samples,
            trigger_reason=trigger_reason,
            retraining_job_id=retraining_job_id,
        ))
    else:
        print(f"[export] No DATABASE_URL set — skipping DB registration")
        print(f"[export] Manually register: GCS path = {gcs_path}, tag = {version_tag}")

    print(f"\n[export] ✓ Done — model {version_tag} is now active")
    return gcs_path


# ──────────────────────────────────────────────
# Standalone entry point (post-Colab training)
# ──────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Export trained PyTorch model to ONNX and register in DB")
    parser.add_argument("--weights", required=True, help="Path to best_weights.pt")
    parser.add_argument("--output-dir", default="/tmp/export_output")
    parser.add_argument("--tag", default=None, help="Version tag e.g. v1.0 (auto-generated if omitted)")
    parser.add_argument("--accuracy", type=float, default=0.0)
    parser.add_argument("--samples", type=int, default=0)
    parser.add_argument("--reason", default="manual")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    model = build_model(settings.num_classes)
    model.load_state_dict(torch.load(args.weights, map_location="cpu"))

    export_and_register(
        model=model,
        output_dir=output_dir,
        val_accuracy=args.accuracy,
        training_samples=args.samples,
        trigger_reason=args.reason,
        version_tag=args.tag,
    )


if __name__ == "__main__":
    main()
