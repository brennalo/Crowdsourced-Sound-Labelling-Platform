"""
train.py — full retraining script.

Run modes:
  1. Initial training on frugalai (Colab):
       python train.py --mode frugalai

  2. Automated retraining on crowdsourced data (Cloud Run Job):
       python train.py --mode retrain
       (reads RETRAINING_JOB_ID from env, updates DB status)

  3. Combined (frugalai + crowdsourced):
       python train.py --mode combined
"""

import argparse
import os
import asyncio
from pathlib import Path
from datetime import datetime, timezone

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, random_split
from sklearn.metrics import classification_report
import numpy as np

from config import get_training_settings
from model import build_model, count_parameters
from dataset import FrugalAIDataset, GCSSegmentDataset, CombinedDataset

settings = get_training_settings()
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")


# ──────────────────────────────────────────────
# Data loading
# ──────────────────────────────────────────────

def load_frugalai_dataset():
    from datasets import load_dataset, Audio
    print("[data] Loading rfcx/frugalai from HuggingFace...")
    hf = load_dataset("rfcx/frugalai", trust_remote_code=True)
    train_split = hf["train"] if "train" in hf else hf[list(hf.keys())[0]]

    train_split = train_split.cast_column('audio', Audio(decode=False))

    # Map frugalai label names → our label names
    # Adjust this mapping based on actual dataset column values
    label_map = {
        "0": "chainsaw",
        "1": "environment",
    }
    return FrugalAIDataset(train_split, label_map=label_map)


async def load_gcs_records() -> list[dict]:
    """Fetch all training_pool segments with an authoritative label from DB.
    (annotations table has been removed — effective_label on segments is now
    the single source of truth for training/export.)"""
    from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
    from sqlalchemy import select
    import sys
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))
    from app.models.segment import Segment

    engine = create_async_engine(settings.database_url)
    Session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with Session() as db:
        result = await db.execute(
            select(Segment).where(
                Segment.review_status == "training_pool",
                Segment.effective_label.isnot(None),
                Segment.is_silent == False,
            )
        )
        segments = result.scalars().all()

    await engine.dispose()
    return [{"gcs_path": seg.gcs_path, "label": seg.effective_label} for seg in segments]
# ──────────────────────────────────────────────
# Training
# ──────────────────────────────────────────────

def train_epoch(model, loader, optimizer, criterion) -> float:
    model.train()
    total_loss = 0.0
    for mels, labels in loader:
        mels, labels = mels.to(DEVICE), labels.to(DEVICE)
        optimizer.zero_grad()
        outputs = model(mels)
        loss = criterion(outputs, labels)
        loss.backward()
        optimizer.step()
        total_loss += loss.item() * mels.size(0)
    return total_loss / len(loader.dataset)


def eval_epoch(model, loader, criterion) -> tuple[float, float]:
    model.eval()
    total_loss = 0.0
    correct = 0
    with torch.no_grad():
        for mels, labels in loader:
            mels, labels = mels.to(DEVICE), labels.to(DEVICE)
            outputs = model(mels)
            loss = criterion(outputs, labels)
            total_loss += loss.item() * mels.size(0)
            preds = outputs.argmax(dim=1)
            correct += (preds == labels).sum().item()
    n = len(loader.dataset)
    return total_loss / n, correct / n


def train(dataset, output_dir: Path) -> dict:
    """
    Full training loop with val split and early stopping.
    Returns metrics dict.
    """
    print(f"[train] Device: {DEVICE}")
    print(f"[train] Dataset size: {len(dataset)}")
    print(f"[train] Model parameters: {count_parameters(build_model(settings.num_classes)):,}")

    val_size = int(len(dataset) * settings.val_split)
    train_size = len(dataset) - val_size
    train_ds, val_ds = random_split(dataset, [train_size, val_size], generator=torch.Generator().manual_seed(42))

    train_loader = DataLoader(train_ds, batch_size=settings.batch_size, shuffle=True, num_workers=2, pin_memory=True)
    val_loader = DataLoader(val_ds, batch_size=settings.batch_size, shuffle=False, num_workers=2, pin_memory=True)

    model = build_model(settings.num_classes).to(DEVICE)
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=settings.learning_rate, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer, patience=3, factor=0.5)

    best_val_acc = 0.0
    best_weights_path = output_dir / "best_weights.pt"
    patience_counter = 0

    for epoch in range(1, settings.num_epochs + 1):
        train_loss = train_epoch(model, train_loader, optimizer, criterion)
        val_loss, val_acc = eval_epoch(model, val_loader, criterion)
        scheduler.step(val_loss)

        print(f"[epoch {epoch:02d}] train_loss={train_loss:.4f} val_loss={val_loss:.4f} val_acc={val_acc:.4f}")

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(model.state_dict(), best_weights_path)
            patience_counter = 0
            print(f"  ✓ Best model saved (val_acc={val_acc:.4f})")
        else:
            patience_counter += 1
            if patience_counter >= settings.early_stopping_patience:
                print(f"[train] Early stopping at epoch {epoch}")
                break

    # Final evaluation with best weights
    model.load_state_dict(torch.load(best_weights_path, map_location=DEVICE))
    _, final_acc = eval_epoch(model, val_loader, criterion)

    print(f"\n[train] Final val accuracy: {final_acc:.4f}")
    print(f"[train] Best val accuracy:  {best_val_acc:.4f}")

    return {
        "model": model,
        "val_accuracy": final_acc,
        "training_samples": train_size,
        "weights_path": best_weights_path,
    }


# ──────────────────────────────────────────────
# DB status update (used by Cloud Run Job)
# ──────────────────────────────────────────────

async def update_retraining_job(job_id: str, status: str, model_version_id: str | None = None, error: str | None = None):
    from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
    from sqlalchemy import select
    import sys
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))
    from app.models.retraining_job import RetrainingJob

    engine = create_async_engine(settings.database_url)
    Session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with Session() as db:
        result = await db.execute(select(RetrainingJob).where(RetrainingJob.id == job_id))
        job = result.scalar_one_or_none()
        if job:
            job.status = status
            job.completed_at = datetime.now(timezone.utc)
            if model_version_id:
                job.model_version_id = model_version_id
            if error:
                job.error_log = error
            await db.commit()

    await engine.dispose()


# ──────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["frugalai", "retrain", "combined"], default="frugalai")
    parser.add_argument("--output-dir", default="/tmp/training_output")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    job_id = settings.retraining_job_id

    try:
        if args.mode == "frugalai":
            dataset = load_frugalai_dataset()

        elif args.mode == "retrain":
            records = asyncio.run(load_gcs_records())
            print(f"[data] Loaded {len(records)} annotated segments from GCS")
            if not records:
                raise ValueError("No annotated segments found in database")
            dataset = GCSSegmentDataset(records)

        elif args.mode == "combined":
            frugalai_ds = load_frugalai_dataset()
            records = asyncio.run(load_gcs_records())
            gcs_ds = GCSSegmentDataset(records) if records else None
            dataset = CombinedDataset([frugalai_ds, gcs_ds]) if gcs_ds else frugalai_ds

        result = train(dataset, output_dir)

        # Export to ONNX and push to GCS
        from export_onnx import export_and_register
        export_and_register(
            model=result["model"],
            output_dir=output_dir,
            val_accuracy=result["val_accuracy"],
            training_samples=result["training_samples"],
            trigger_reason="manual" if not job_id else "active_learning",
            retraining_job_id=job_id or None,
        )

    except Exception as e:
        print(f"[train] FAILED: {e}")
        if job_id and settings.database_url:
            asyncio.run(update_retraining_job(job_id, "failed", error=str(e)))
        raise


if __name__ == "__main__":
    main()
