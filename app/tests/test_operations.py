from __future__ import annotations

from unittest.mock import patch

from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError


def test_liveness(client: TestClient) -> None:
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readiness_ok(client: TestClient) -> None:
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.json()["checks"]["database"] == "ok"


def test_readiness_reports_database_failure(client: TestClient) -> None:
    with patch(
        "sqlalchemy.orm.Session.execute",
        side_effect=OperationalError("SELECT 1", {}, Exception("connection refused")),
    ):
        response = client.get("/readyz")
    assert response.status_code == 503
    assert response.json()["checks"]["database"] == "failing"


def test_liveness_does_not_depend_on_database(client: TestClient) -> None:
    with patch(
        "sqlalchemy.orm.Session.execute", side_effect=OperationalError("x", {}, Exception())
    ):
        assert client.get("/healthz").status_code == 200


def test_version_reports_build(client: TestClient) -> None:
    body = client.get("/version").json()
    assert body == {"version": "9.9.9", "git_sha": "abc1234", "environment": "test"}


def test_metrics_use_route_templates(client: TestClient) -> None:
    client.get("/api/v1/matters/3fa85f64-5717-4562-b3fc-2c963f66afa6")
    text = client.get("/metrics").text
    assert "http_requests_total" in text
    assert 'route="/api/v1/matters/{matter_id}"' in text
    assert "3fa85f64" not in text  # raw IDs must never become label values


def test_security_headers_and_request_id(client: TestClient) -> None:
    response = client.get("/healthz", headers={"X-Request-ID": "trace-123"})
    assert response.headers["X-Request-ID"] == "trace-123"
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert "max-age" in response.headers["Strict-Transport-Security"]


def test_malformed_request_id_is_replaced(client: TestClient) -> None:
    response = client.get("/healthz", headers={"X-Request-ID": "bad id\nwith newline"})
    assert response.headers["X-Request-ID"] != "bad id\nwith newline"
    assert len(response.headers["X-Request-ID"]) == 32
