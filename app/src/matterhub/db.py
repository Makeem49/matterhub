"""Database engine and session management (SQLAlchemy 2.x)."""

from __future__ import annotations

from collections.abc import Iterator
from typing import Annotated, Any

from fastapi import Depends, Request
from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool

from matterhub.config import Settings


class Base(DeclarativeBase):
    pass


def build_engine(settings: Settings) -> Engine:
    url = settings.sqlalchemy_url()
    kwargs: dict[str, Any] = {"pool_pre_ping": True}
    if url.get_backend_name() == "sqlite":
        kwargs["connect_args"] = {"check_same_thread": False}
        if url.database in (None, "", ":memory:"):
            # One shared in-memory database for the whole process (used by tests).
            kwargs["poolclass"] = StaticPool
    else:
        # Small pool per pod; horizontal scaling happens with replicas, so keep
        # pool_size * max_replicas below the PostgreSQL connection limit.
        kwargs.update(pool_size=5, max_overflow=5, pool_recycle=1800, pool_timeout=10)
    return create_engine(url, **kwargs)


def build_session_factory(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(bind=engine, expire_on_commit=False)


def get_session(request: Request) -> Iterator[Session]:
    factory: sessionmaker[Session] = request.app.state.session_factory
    with factory() as session:
        yield session


SessionDep = Annotated[Session, Depends(get_session)]
