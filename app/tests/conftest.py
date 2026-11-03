from __future__ import annotations

import os
import time
from collections.abc import Iterator
from dataclasses import dataclass
from typing import Any

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from matterhub.auth import TokenValidator
from matterhub.config import Settings
from matterhub.db import Base
from matterhub.main import create_app

TENANT_ID = "11111111-2222-3333-4444-555555555555"
AUDIENCE = "api://matterhub-test"


def _database_url() -> str:
    # CI's integration job points this at a PostgreSQL service container.
    return os.environ.get("MATTERHUB_TEST_DATABASE_URL", "sqlite://")


def make_settings(**overrides: Any) -> Settings:
    values: dict[str, Any] = {
        "environment": "test",
        "database_url": _database_url(),
        "auth_mode": "disabled",
        "log_json": False,
        "log_level": "WARNING",
        "app_version": "9.9.9",
        "git_sha": "abc1234",
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


def _client_for(settings: Settings) -> Iterator[TestClient]:
    app = create_app(settings)
    engine = app.state.engine
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    with TestClient(app) as client:
        yield client
    Base.metadata.drop_all(engine)
    engine.dispose()


@pytest.fixture
def client() -> Iterator[TestClient]:
    yield from _client_for(make_settings())


# --------------------------------------------------------------------------- Entra ID


@dataclass
class _Key:
    key: Any


class FakeJwks:
    """Stands in for Entra ID's JWKS endpoint so tests run offline."""

    def __init__(self) -> None:
        self.private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    def get_signing_key_from_jwt(self, token: str) -> _Key:
        return _Key(self.private_key.public_key())

    def issue(self, roles: list[str] | None = None, **claim_overrides: Any) -> str:
        now = int(time.time())
        claims: dict[str, Any] = {
            "iss": f"https://login.microsoftonline.com/{TENANT_ID}/v2.0",
            "aud": AUDIENCE,
            "sub": "subject-1",
            "oid": "00000000-0000-0000-0000-00000000abcd",
            "preferred_username": "jane.lawyer@example.gov.uk",
            "iat": now,
            "nbf": now,
            "exp": now + 600,
            "roles": roles or [],
        }
        claims.update(claim_overrides)
        return jwt.encode(claims, self.private_key, algorithm="RS256")


@pytest.fixture
def jwks() -> FakeJwks:
    return FakeJwks()


@pytest.fixture
def secured_client(jwks: FakeJwks) -> Iterator[TestClient]:
    settings = make_settings(auth_mode="entra", entra_tenant_id=TENANT_ID, entra_audience=AUDIENCE)
    app = create_app(settings)
    app.state.token_validator = TokenValidator(TENANT_ID, AUDIENCE, jwks_client=jwks)
    engine = app.state.engine
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    with TestClient(app) as client:
        yield client
    Base.metadata.drop_all(engine)
    engine.dispose()


def sample_matter(**overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "title": "Judicial review of planning decision",
        "client_department": "Department for Levelling Up",
        "practice_area": "public_law",
        "owner": "jane.lawyer@example.gov.uk",
    }
    body.update(overrides)
    return body
