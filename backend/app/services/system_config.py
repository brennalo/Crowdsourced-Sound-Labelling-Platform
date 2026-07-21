# Programmer Name : Brenna Lo
# Program Name : system_config.py
# Description : System configuration management service for fetching the singleton system_config row
# First Written on : 2024-06-10
# Edited on : 2024-07-18

"""
Reads the singleton system_config row at call time — deliberately NOT cached
at process/module level, so a researcher's change is picked up by the very
next Celery task or request, with no redeploy or restart needed.
"""
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.system_config import SystemConfig


async def get_system_config(db: AsyncSession) -> SystemConfig:
    """Fetch the singleton config row, creating it with defaults if this is
    the first time the app has run against this database."""
    result = await db.execute(select(SystemConfig).where(SystemConfig.id == 1))
    config = result.scalar_one_or_none()
    if config is None:
        config = SystemConfig(id=1)
        db.add(config)
        await db.commit()
        await db.refresh(config)
    return config
