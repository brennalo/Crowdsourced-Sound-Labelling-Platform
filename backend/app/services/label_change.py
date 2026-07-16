import uuid
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.label_change import LabelChange


async def record_label_change(
    db: AsyncSession,
    *,
    segment_id: uuid.UUID,
    change_source: str,
    old_label: str | None,
    new_label: str | None,
    changed_by_user_id: uuid.UUID | None = None,
) -> LabelChange:
    """
    Single write path for the label_changes audit log.
    Call this at every point effective_label changes (or a researcher confirms it unchanged).
    Does NOT commit — caller commits as part of its own transaction so the label
    update and the audit row land atomically.
    """
    change = LabelChange(
        segment_id=segment_id,
        changed_by_user_id=changed_by_user_id,
        change_source=change_source,
        old_label=old_label,
        new_label=new_label,
    )
    db.add(change)
    return change