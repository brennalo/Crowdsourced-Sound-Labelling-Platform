# Programmer Name : Brenna Lo
# Program Name : main.py
# Description : Main application entry point
# First Written on : 2024-06-10
# Edited on : 2024-07-18

from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select

from app.config import get_settings
from app.database import AsyncSessionLocal
from app.models.model_version import ModelVersion
from app.services.inference import load_active_model_from_gcs
from app.routers.auth import router as auth_router
from app.routers.recordings import router as recordings_router
from app.routers.segments import router as segments_router
from app.routers.labels import router as labels_router
from app.routers.suggestions import router as suggestions_router
from app.routers.consensus import router as consensus_router
from app.routers.training_pool import router as training_pool_router
from app.routers.researcher import router as researcher_router
from app.routers.export import router as export_router
from app.routers.model import router as model_router
from app.routers.config import router as config_router
from app.routers.admin import router as admin_router
from app.routers.device_tokens import router as device_tokens_router

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(ModelVersion).where(ModelVersion.is_active == True))
        active_model = result.scalar_one_or_none()
        if active_model:
            try:
                load_active_model_from_gcs(active_model.gcs_model_path)
                print(f"[startup] Loaded model {active_model.version_tag}")
            except Exception as e:
                print(f"[startup] Warning: could not load model — {e}")
        else:
            print("[startup] No active model — inference disabled until model is registered")
    yield


app = FastAPI(
    title="Forest Sound Platform",
    description="Crowdsourced forest sound collection for illegal logging detection",
    version="0.2.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://crowdsourced-sound-labelling.web.app",
        "https://crowdsourced-sound-labelling.firebaseapp.com",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(recordings_router)
app.include_router(segments_router)
app.include_router(labels_router)
app.include_router(suggestions_router)
app.include_router(consensus_router)
app.include_router(training_pool_router)
app.include_router(researcher_router)
app.include_router(export_router)
app.include_router(model_router)
app.include_router(config_router)
app.include_router(admin_router)
app.include_router(device_tokens_router)


@app.get("/health")
async def health():
    return {"status": "ok"}
