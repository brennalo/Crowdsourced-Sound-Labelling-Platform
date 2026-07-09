from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.label import Label
from app.schemas.segment import LabelOut
from app.auth import get_current_user

router = APIRouter(prefix="/labels", tags=["labels"])


@router.get("/", response_model=list[LabelOut])
async def list_labels(
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    """All active labels. Flutter fetches this on app start and caches."""
    result = await db.execute(
        select(Label).where(Label.is_active == True).order_by(Label.name)
    )
    return [LabelOut.model_validate(l) for l in result.scalars().all()]
