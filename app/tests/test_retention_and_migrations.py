from __future__ import annotations

from datetime import UTC, date, datetime
from pathlib import Path

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import create_engine, inspect

import matterhub
from matterhub.config import Settings
from matterhub.db import Base, build_engine, build_session_factory
from matterhub.jobs import retention
from matterhub.models import AuditEvent, Matter, MatterStatus, PracticeArea

from .conftest import make_settings

MIGRATIONS = Path(matterhub.__file__).parent / "migrations"


@pytest.fixture
def session():  # type: ignore[no-untyped-def]
    engine = build_engine(make_settings())
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    with build_session_factory(engine)() as s:
        yield s
    Base.metadata.drop_all(engine)
    engine.dispose()


def _matter(ref: str, status: MatterStatus, retention_until: date | None) -> Matter:
    return Matter(
        reference=ref,
        title="Contract dispute",
        client_department="HM Treasury",
        practice_area=PracticeArea.COMMERCIAL,
        status=status,
        owner="owner@example.gov.uk",
        created_by="tests",
        retention_until=retention_until,
        closed_at=datetime(2019, 1, 1, tzinfo=UTC) if status == MatterStatus.CLOSED else None,
    )


def test_retention_flags_only_due_matters(session) -> None:  # type: ignore[no-untyped-def]
    today = date(2026, 11, 3)
    session.add_all(
        [
            _matter("MAT-DUE", MatterStatus.CLOSED, date(2026, 1, 1)),
            _matter("MAT-TODAY", MatterStatus.CLOSED, today),
            _matter("MAT-FUTURE", MatterStatus.CLOSED, date(2030, 1, 1)),
            _matter("MAT-OPEN", MatterStatus.OPEN, None),
        ]
    )
    session.commit()

    result = retention.run_retention(session, today)
    assert result.flagged == 2

    flagged = {m.reference for m in session.query(Matter) if m.retention_flagged_at is not None}
    assert flagged == {"MAT-DUE", "MAT-TODAY"}
    assert session.query(AuditEvent).filter_by(action="retention_flagged").count() == 2

    # Idempotent: a second run (e.g. a CronJob retry) changes nothing.
    assert retention.run_retention(session, today).flagged == 0


def test_retention_dry_run_changes_nothing(session) -> None:  # type: ignore[no-untyped-def]
    session.add(_matter("MAT-DUE", MatterStatus.CLOSED, date(2020, 1, 1)))
    session.commit()
    assert retention.run_retention(session, date(2026, 11, 3), dry_run=True).flagged == 1
    assert session.query(AuditEvent).count() == 0
    assert retention.run_retention(session, date(2026, 11, 3)).flagged == 1


def test_retention_main_exit_codes(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    db = tmp_path / "job.db"
    settings = make_settings(database_url=f"sqlite:///{db}")
    setup_engine = create_engine(f"sqlite:///{db}")
    Base.metadata.create_all(setup_engine)
    setup_engine.dispose()
    monkeypatch.setattr(retention, "get_settings", lambda: settings)
    assert retention.main() == 0

    broken: Settings = make_settings(database_url=f"sqlite:///{tmp_path}/missing/dir/x.db")
    monkeypatch.setattr(retention, "get_settings", lambda: broken)
    assert retention.main() == 1


def _alembic_config(url: str) -> Config:
    cfg = Config()
    cfg.set_main_option("script_location", str(MIGRATIONS))
    cfg.set_main_option("sqlalchemy.url", url)
    return cfg


def test_migrations_upgrade_and_downgrade(tmp_path: Path) -> None:
    url = f"sqlite:///{tmp_path / 'migrate.db'}"
    cfg = _alembic_config(url)
    command.upgrade(cfg, "head")
    assert {"matters", "audit_events", "alembic_version"} <= _tables(url)
    command.downgrade(cfg, "base")
    assert _tables(url) == {"alembic_version"}


def _tables(url: str) -> set[str]:
    engine = create_engine(url)
    try:
        return set(inspect(engine).get_table_names())
    finally:
        engine.dispose()


def test_models_and_migrations_are_in_sync(tmp_path: Path) -> None:
    """Fails CI if someone changes a model without writing a migration."""
    url = f"sqlite:///{tmp_path / 'drift.db'}"
    command.upgrade(_alembic_config(url), "head")
    engine = create_engine(url)
    with engine.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
    engine.dispose()
    assert diff == [], f"Schema drift detected - generate a migration: {diff}"
