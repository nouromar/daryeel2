from __future__ import annotations

import os

from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.orm import sessionmaker


def database_url() -> str:
    return os.getenv("API_DATABASE_URL") or os.getenv("DATABASE_URL") or ""


def create_engine_from_env():
    url = database_url()
    if not url:
        raise RuntimeError("DATABASE_URL (or API_DATABASE_URL) is not set")
    return create_engine(url, pool_pre_ping=True)


SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=None)

_engine = None


def get_engine():
    global _engine
    if _engine is None:
        _engine = create_engine_from_env()
        SessionLocal.configure(bind=_engine)
    return _engine


def get_db() -> Session:
    # FastAPI dependency.
    get_engine()
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
