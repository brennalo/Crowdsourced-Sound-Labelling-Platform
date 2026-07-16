from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from urllib.parse import urlparse, urlunparse
from app.config import get_settings
import ssl
from sqlalchemy.pool import NullPool

settings = get_settings()

# asyncpg requires ssl context object, not sslmode string
# Strip any ?ssl= or ?sslmode= params from URL first to avoid conflicts
from urllib.parse import urlparse, urlunparse

database_url = settings.database_url
parsed = urlparse(database_url)
# Reconstruct with no query string — asyncpg doesn't use URL query params anyway
database_url = urlunparse(parsed._replace(query=""))

# Build SSL context for Neon
ssl_context = ssl.create_default_context()

engine_kwargs = {
    "echo": False,
    "connect_args": {"ssl": ssl_context},
}
if settings.is_celery_worker:
    engine_kwargs["poolclass"] = NullPool
else:
    engine_kwargs["pool_pre_ping"] = True

engine = create_async_engine(database_url, **engine_kwargs)

AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()