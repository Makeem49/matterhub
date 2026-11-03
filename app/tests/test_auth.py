from __future__ import annotations

import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from .conftest import AUDIENCE, FakeJwks, make_settings, sample_matter


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_missing_token_is_401(secured_client: TestClient) -> None:
    response = secured_client.get("/api/v1/matters")
    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"


def test_operational_endpoints_stay_public(secured_client: TestClient) -> None:
    assert secured_client.get("/healthz").status_code == 200
    assert secured_client.get("/readyz").status_code == 200


def test_reader_can_read_but_not_write(secured_client: TestClient, jwks: FakeJwks) -> None:
    token = jwks.issue(roles=["Matters.Read"])
    assert secured_client.get("/api/v1/matters", headers=_auth(token)).status_code == 200
    response = secured_client.post("/api/v1/matters", json=sample_matter(), headers=_auth(token))
    assert response.status_code == 403


def test_writer_identity_is_recorded(secured_client: TestClient, jwks: FakeJwks) -> None:
    token = jwks.issue(roles=["Matters.Write"])
    response = secured_client.post("/api/v1/matters", json=sample_matter(), headers=_auth(token))
    assert response.status_code == 201
    assert response.json()["created_by"] == "jane.lawyer@example.gov.uk"


def test_admin_role_implies_everything(secured_client: TestClient, jwks: FakeJwks) -> None:
    token = jwks.issue(roles=["Matters.Admin"])
    response = secured_client.post("/api/v1/matters", json=sample_matter(), headers=_auth(token))
    assert response.status_code == 201


def test_no_roles_is_forbidden(secured_client: TestClient, jwks: FakeJwks) -> None:
    response = secured_client.get("/api/v1/matters", headers=_auth(jwks.issue(roles=[])))
    assert response.status_code == 403


@pytest.mark.parametrize(
    "claims",
    [
        {"exp": int(time.time()) - 3600},  # expired
        {"aud": "api://some-other-api"},  # token for another API
        {"iss": "https://login.microsoftonline.com/evil-tenant/v2.0"},  # other tenant
    ],
    ids=["expired", "wrong-audience", "wrong-issuer"],
)
def test_bad_tokens_are_rejected(secured_client: TestClient, jwks: FakeJwks, claims: dict) -> None:
    token = jwks.issue(roles=["Matters.Admin"], **claims)
    assert secured_client.get("/api/v1/matters", headers=_auth(token)).status_code == 401


def test_token_signed_by_unknown_key_is_rejected(secured_client: TestClient) -> None:
    attacker = FakeJwks()  # different private key
    token = attacker.issue(roles=["Matters.Admin"])
    assert secured_client.get("/api/v1/matters", headers=_auth(token)).status_code == 401


def test_auth_cannot_be_disabled_in_production() -> None:
    with pytest.raises(ValidationError, match="not permitted in prod"):
        make_settings(environment="prod", auth_mode="disabled")


def test_entra_mode_requires_tenant_and_audience() -> None:
    with pytest.raises(ValidationError, match="entra_tenant_id"):
        make_settings(auth_mode="entra", entra_audience=AUDIENCE)


def test_deployed_environments_require_postgres() -> None:
    with pytest.raises(ValidationError, match="PostgreSQL"):
        make_settings(environment="dev", database_url=None)


def test_secrets_are_read_from_key_vault_mount(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The Key Vault CSI driver mounts each secret as a file; config must pick it up."""
    from matterhub.config import get_settings

    (tmp_path / "matterhub_database_password").write_text("from-key-vault")
    monkeypatch.setenv("MATTERHUB_SECRETS_DIR", str(tmp_path))
    monkeypatch.setenv("MATTERHUB_AUTH_MODE", "disabled")
    monkeypatch.setenv("MATTERHUB_DATABASE_HOST", "pg.example.internal")
    get_settings.cache_clear()
    try:
        settings = get_settings()
        assert settings.database_password is not None
        assert settings.database_password.get_secret_value() == "from-key-vault"
        url = settings.sqlalchemy_url()
        assert url.password == "from-key-vault"
        assert url.query["sslmode"] == "require"
        assert "from-key-vault" not in repr(settings)  # SecretStr never leaks into logs
    finally:
        get_settings.cache_clear()
