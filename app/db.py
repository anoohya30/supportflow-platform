"""Database connection setup (SQLAlchemy)."""

from collections.abc import Iterator

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

from app import config


def make_engine(url: str = config.DATABASE_URL) -> Engine:
    timeout = config.DB_CHECK_TIMEOUT_SECONDS
    return create_engine(
        url,
        pool_pre_ping=True,  # drop dead connections instead of failing requests
        pool_size=5,
        max_overflow=5,
        pool_timeout=timeout,
        connect_args={
            # Give up connecting after N seconds instead of hanging.
            "connect_timeout": timeout,
            # Cancel any single SQL statement that runs longer than N seconds.
            "options": f"-c statement_timeout={timeout * 1000}",
        },
    )


engine = make_engine()


def get_engine() -> Engine:
    return engine


def get_session() -> Iterator[Session]:
    """FastAPI dependency: one database session per request."""
    with Session(engine) as session:
        yield session


def database_is_reachable(db_engine: Engine) -> bool:
    """Bounded connectivity check used by GET /health/ready."""
    try:
        with db_engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False
