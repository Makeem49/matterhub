"""Alembic environment. The database URL comes from MatterHub settings unless the
caller sets ``sqlalchemy.url`` explicitly (tests do this)."""

from __future__ import annotations

from alembic import context
from sqlalchemy import Connection, create_engine

from matterhub import models  # noqa: F401 - registers tables on Base.metadata
from matterhub.config import get_settings
from matterhub.db import Base, build_engine

config = context.config
target_metadata = Base.metadata


def _configure_and_run(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
        render_as_batch=connection.dialect.name == "sqlite",
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_offline() -> None:
    url = config.get_main_option(
        "sqlalchemy.url"
    ) or get_settings().sqlalchemy_url().render_as_string(hide_password=False)
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    url = config.get_main_option("sqlalchemy.url")
    engine = create_engine(url) if url else build_engine(get_settings())
    try:
        with engine.connect() as connection:
            _configure_and_run(connection)
    finally:
        engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
