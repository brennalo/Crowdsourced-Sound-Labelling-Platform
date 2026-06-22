from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select

from app.config import get_settings
from app.database import AsyncSessionLocal
from app.models.model_version import ModelVersion
from app.services.inference import load_active_model_from_gcs
from app.routers import (
    auth_router,
    recordings_router,
    segments_router,
    annotations_router,
    suggestions_router,
    export_router,
    model_router,
)

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # On startup: load active ONNX model from GCS into memory
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(ModelVersion).where(ModelVersion.is_active == True)
        )
        active_model = result.scalar_one_or_none()
        if active_model:
            try:
                load_active_model_from_gcs(active_model.gcs_model_path)
                print(f"[startup] Loaded model {active_model.version_tag}")
            except Exception as e:
                print(f"[startup] Warning: could not load model — {e}")
        else:
            print("[startup] No active model found — inference disabled until model is registered")

    yield
    # Shutdown cleanup (nothing needed currently)


app = FastAPI(
    title="Forest Sound Platform",
    description="Crowdsourced forest sound collection for illegal logging detection",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Tighten in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(recordings_router)
app.include_router(segments_router)
app.include_router(annotations_router)
app.include_router(suggestions_router)
app.include_router(export_router)
app.include_router(model_router)


@app.get("/health")
async def health():
    return {"status": "ok"}
