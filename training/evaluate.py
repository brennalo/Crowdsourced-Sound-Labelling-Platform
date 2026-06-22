"""
evaluate.py — run evaluation on a saved ONNX model against a labelled dataset.

Usage:
  python evaluate.py --model gs://bucket/models/v1.0/model.onnx --mode frugalai
  python evaluate.py --model /local/path/model.onnx --mode retrain
"""

import argparse
import asyncio
import numpy as np
import onnxruntime as ort
from torch.utils.data import DataLoader
from sklearn.metrics import classification_report, confusion_matrix

from config import get_training_settings
from dataset import FrugalAIDataset, GCSSegmentDataset

settings = get_training_settings()
LABELS = settings.labels


def load_onnx_session(model_path: str) -> ort.InferenceSession:
    if model_path.startswith("gs://"):
        from google.cloud import storage
        parts = model_path[5:].split("/", 1)
        bucket_name, blob_path = parts[0], parts[1]
        client = storage.Client()
        blob = client.bucket(bucket_name).blob(blob_path)
        model_bytes = blob.download_as_bytes()
        return ort.InferenceSession(model_bytes, providers=["CPUExecutionProvider"])
    else:
        return ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])


def evaluate(session: ort.InferenceSession, loader: DataLoader) -> dict:
    input_name = session.get_inputs()[0].name
    all_preds = []
    all_labels = []

    for mels, labels in loader:
        mels_np = mels.numpy()
        outputs = session.run(None, {input_name: mels_np})
        logits = outputs[0]
        preds = np.argmax(logits, axis=1)
        all_preds.extend(preds.tolist())
        all_labels.extend(labels.tolist())

    all_preds = np.array(all_preds)
    all_labels = np.array(all_labels)

    accuracy = (all_preds == all_labels).mean()
    report = classification_report(all_labels, all_preds, target_names=LABELS, digits=4)
    cm = confusion_matrix(all_labels, all_preds)

    return {
        "accuracy": accuracy,
        "report": report,
        "confusion_matrix": cm,
    }


async def load_gcs_records() -> list[dict]:
    from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
    from sqlalchemy import select
    import sys, os
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))
    from app.models.annotation import Annotation
    from app.models.segment import Segment

    engine = create_async_engine(settings.database_url)
    Session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with Session() as db:
        result = await db.execute(
            select(Annotation, Segment)
            .join(Segment, Annotation.segment_id == Segment.id)
            .where(Annotation.source == "manual", Segment.is_silent == False)
        )
        rows = result.all()
    await engine.dispose()
    return [{"gcs_path": seg.gcs_path, "label": ann.label} for ann, seg in rows]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="ONNX model path (local or gs://)")
    parser.add_argument("--mode", choices=["frugalai", "retrain"], default="frugalai")
    args = parser.parse_args()

    print(f"[eval] Loading model: {args.model}")
    session = load_onnx_session(args.model)

    if args.mode == "frugalai":
        from datasets import load_dataset
        hf = load_dataset("rfcx/frugalai", trust_remote_code=True)
        split = hf.get("test") or hf.get("validation") or list(hf.values())[0]
        label_map = {
            "chainsaw": "chainsaw", "environment": "environment",
            "no_chainsaw": "environment", "background": "environment",
            "positive": "chainsaw", "negative": "environment",
        }
        dataset = FrugalAIDataset(split, label_map=label_map)
    else:
        records = asyncio.run(load_gcs_records())
        dataset = GCSSegmentDataset(records)

    loader = DataLoader(dataset, batch_size=32, shuffle=False, num_workers=2)
    print(f"[eval] Evaluating on {len(dataset)} samples...")

    results = evaluate(session, loader)

    print(f"\n[eval] Accuracy: {results['accuracy']:.4f}")
    print(f"\n[eval] Classification Report:\n{results['report']}")
    print(f"\n[eval] Confusion Matrix:")
    print(f"       {' '.join(f'{l:>12}' for l in LABELS)}")
    for i, row in enumerate(results["confusion_matrix"]):
        print(f"  {LABELS[i]:>12} {row}")


if __name__ == "__main__":
    main()
