from __future__ import annotations

import json
import logging
from pathlib import Path
from unittest.mock import patch

import pytest
from sqlalchemy import create_engine, inspect

from matterhub import __main__ as cli
from matterhub.logging_config import JsonFormatter, configure_logging, request_id_ctx

from .conftest import make_settings


def test_serve_runs_uvicorn_with_hardened_options() -> None:
    with patch("uvicorn.run") as run:
        assert cli.main(["serve", "--port", "9000"]) == 0
    kwargs = run.call_args.kwargs
    assert kwargs["factory"] is True
    assert kwargs["port"] == 9000
    assert kwargs["server_header"] is False
    assert kwargs["log_config"] is None


def test_migrate_applies_schema(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    url = f"sqlite:///{tmp_path / 'cli.db'}"
    monkeypatch.setattr("matterhub.config.get_settings", lambda: make_settings(database_url=url))
    assert cli.main(["migrate"]) == 0
    engine = create_engine(url)
    assert "matters" in inspect(engine).get_table_names()
    engine.dispose()


def test_retention_command_passes_dry_run() -> None:
    with patch("matterhub.jobs.retention.main", return_value=0) as job:
        assert cli.main(["retention", "--dry-run"]) == 0
    job.assert_called_once_with(dry_run=True)


def test_cli_requires_a_command() -> None:
    with pytest.raises(SystemExit):
        cli.main([])


def test_json_formatter_includes_context_and_extras() -> None:
    configure_logging("INFO", json_logs=True)
    record = logging.LogRecord("matterhub.test", logging.INFO, __file__, 1, "hello", None, None)
    record.matter_id = "m-1"
    token = request_id_ctx.set("req-42")
    try:
        logging.getLogger().handlers[0].filter(record)
        payload = json.loads(JsonFormatter().format(record))
    finally:
        request_id_ctx.reset(token)
    assert payload["message"] == "hello"
    assert payload["level"] == "INFO"
    assert payload["request_id"] == "req-42"
    assert payload["matter_id"] == "m-1"
    assert payload["timestamp"].endswith("Z")


def test_json_formatter_renders_exceptions() -> None:
    try:
        raise RuntimeError("boom")
    except RuntimeError:
        import sys

        record = logging.LogRecord("x", logging.ERROR, __file__, 1, "failed", None, sys.exc_info())
    payload = json.loads(JsonFormatter().format(record))
    assert "RuntimeError: boom" in payload["exception"]


def test_plain_text_logging_mode() -> None:
    configure_logging("DEBUG", json_logs=False)
    root = logging.getLogger()
    assert root.level == logging.DEBUG
    assert not isinstance(root.handlers[0].formatter, JsonFormatter)
    assert logging.getLogger("uvicorn.access").disabled is True
