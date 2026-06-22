from app.routers.auth import router as auth_router
from app.routers.recordings import router as recordings_router
from app.routers.segments import router as segments_router
from app.routers.annotations import router as annotations_router
from app.routers.suggestions import router as suggestions_router
from app.routers.export import router as export_router
from app.routers.model import router as model_router

__all__ = [
    "auth_router",
    "recordings_router",
    "segments_router",
    "annotations_router",
    "suggestions_router",
    "export_router",
    "model_router",
]
