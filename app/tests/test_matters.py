from __future__ import annotations

from datetime import UTC, date, datetime

from fastapi.testclient import TestClient

from matterhub.routers.matters import add_years

from .conftest import sample_matter


def test_create_matter(client: TestClient) -> None:
    response = client.post("/api/v1/matters", json=sample_matter())
    assert response.status_code == 201
    body = response.json()
    assert body["reference"].startswith(f"MAT-{datetime.now(UTC):%Y}-")
    assert body["status"] == "open"
    assert body["classification"] == "OFFICIAL"
    assert body["created_by"] == "local-developer"
    assert response.headers["Location"].endswith(f"/api/v1/matters/{body['id']}")


def test_create_rejects_unknown_fields(client: TestClient) -> None:
    response = client.post("/api/v1/matters", json=sample_matter(status="closed"))
    assert response.status_code == 422


def test_create_validates_input(client: TestClient) -> None:
    response = client.post("/api/v1/matters", json=sample_matter(title="x", practice_area="tax"))
    assert response.status_code == 422
    fields = {err["loc"][-1] for err in response.json()["detail"]}
    assert fields == {"title", "practice_area"}


def test_get_and_404(client: TestClient) -> None:
    created = client.post("/api/v1/matters", json=sample_matter()).json()
    assert client.get(f"/api/v1/matters/{created['id']}").json()["title"] == created["title"]
    missing = client.get("/api/v1/matters/3fa85f64-5717-4562-b3fc-2c963f66afa6")
    assert missing.status_code == 404


def test_list_filters_and_pagination(client: TestClient) -> None:
    for i in range(5):
        client.post(
            "/api/v1/matters",
            json=sample_matter(title=f"Employment tribunal {i}", practice_area="employment"),
        )
    client.post("/api/v1/matters", json=sample_matter(practice_area="commercial"))

    page = client.get("/api/v1/matters", params={"practice_area": "employment", "limit": 2}).json()
    assert page["total"] == 5
    assert len(page["items"]) == 2
    assert page["limit"] == 2

    everything = client.get("/api/v1/matters", params={"limit": 100}).json()
    assert everything["total"] == 6

    assert client.get("/api/v1/matters", params={"limit": 1000}).status_code == 422


def test_closing_sets_retention_and_reopening_clears_it(client: TestClient) -> None:
    created = client.post("/api/v1/matters", json=sample_matter()).json()
    url = f"/api/v1/matters/{created['id']}"

    closed = client.patch(url, json={"status": "closed"}).json()
    assert closed["status"] == "closed"
    assert closed["closed_at"] is not None
    expected = add_years(datetime.now(UTC).date(), 7)
    assert closed["retention_until"] == expected.isoformat()

    closed_filter = client.get("/api/v1/matters", params={"status": "closed"}).json()
    assert closed_filter["total"] == 1

    reopened = client.patch(url, json={"status": "open"}).json()
    assert reopened["closed_at"] is None
    assert reopened["retention_until"] is None


def test_update_requires_fields(client: TestClient) -> None:
    created = client.post("/api/v1/matters", json=sample_matter()).json()
    response = client.patch(f"/api/v1/matters/{created['id']}", json={})
    assert response.status_code == 422


def test_audit_trail_records_every_change(client: TestClient) -> None:
    created = client.post("/api/v1/matters", json=sample_matter()).json()
    url = f"/api/v1/matters/{created['id']}"
    client.patch(url, json={"title": "Judicial review - amended grounds"})
    client.patch(url, json={"title": "Judicial review - amended grounds"})  # no-op, no event
    client.patch(url, json={"status": "on_hold"})

    events = client.get(f"{url}/audit").json()
    assert [e["action"] for e in events] == ["created", "updated", "updated"]
    assert events[1]["details"]["changes"]["title"][1] == "Judicial review - amended grounds"
    assert events[2]["details"]["changes"]["status"] == ["open", "on_hold"]


def test_audit_trail_404_for_unknown_matter(client: TestClient) -> None:
    response = client.get("/api/v1/matters/3fa85f64-5717-4562-b3fc-2c963f66afa6/audit")
    assert response.status_code == 404


def test_add_years_handles_leap_day() -> None:
    assert add_years(date(2028, 2, 29), 7) == date(2035, 2, 28)
    assert add_years(date(2026, 11, 3), 7) == date(2033, 11, 3)
