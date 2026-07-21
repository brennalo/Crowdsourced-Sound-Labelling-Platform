# Programmer Name : Brenna Lo
# Program Name : labels.py
# Description : Label API endpoints for managing labels
# First Written on : 2024-06-10
# Edited on : 2024-07-18

import uuid
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.label import Label
from app.models.user import User
from app.schemas.label import LabelOut, LabelCreate, LabelUpdate
from app.auth import get_current_user, require_researcher

router = APIRouter(prefix="/labels", tags=["labels"])


@router.get("/", response_model=list[LabelOut])
async def list_labels(
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    """Active labels only. Flutter fetches this on app start and caches."""
    result = await db.execute(
        select(Label).where(Label.is_active == True).order_by(Label.name)
    )
    return [LabelOut.model_validate(l) for l in result.scalars().all()]


@router.get("/all", response_model=list[LabelOut])
async def list_all_labels(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_researcher),
):
    """All labels including inactive — researcher management screen only."""
    result = await db.execute(select(Label).order_by(Label.name))
    return [LabelOut.model_validate(l) for l in result.scalars().all()]


@router.post("/", response_model=LabelOut, status_code=status.HTTP_201_CREATED)
async def create_label(
    body: LabelCreate,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_researcher),
):
    """Researcher adds a new label to the taxonomy."""
    existing = await db.execute(select(Label).where(Label.name == body.name))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Label name already exists")

    label = Label(
        id=uuid.uuid4(),
        name=body.name,
        display_name=body.display_name,
        is_active=True,
    )
    db.add(label)
    await db.commit()
    await db.refresh(label)
    return LabelOut.model_validate(label)


@router.patch("/{label_id}", response_model=LabelOut)
async def update_label(
    label_id: uuid.UUID,
    body: LabelUpdate,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_researcher),
):
    """Researcher activates/deactivates a label. No name editing — effective_label
    stores the raw name string, so renaming would require a segments migration too."""
    result = await db.execute(select(Label).where(Label.id == label_id))
    label = result.scalar_one_or_none()
    if not label:
        raise HTTPException(status_code=404, detail="Label not found")

    label.is_active = body.is_active
    await db.commit()
    await db.refresh(label)
    return LabelOut.model_validate(label)