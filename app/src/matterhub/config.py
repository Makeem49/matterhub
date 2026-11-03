"""Application configuration.

All settings come from environment variables prefixed with ``MATTERHUB_`` (12-factor).
In Kubernetes, non-secret values come from a ConfigMap and secrets are mounted from
Azure Key Vault through the Secrets Store CSI driver, then exposed as env vars.

Secure defaults: authentication is ON unless explicitly disabled, and it can never be
disabled in staging or production - the app refuses to start.
"""

from __future__ import annotations

import os
from functools import lru_cache
from typing import Literal

from pydantic import AliasChoices, Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import URL, make_url

Environment = Literal["local", "test", "dev", "staging", "prod"]
DEPLOYED_ENVIRONMENTS: frozenset[str] = frozenset({"dev", "staging", "prod"})
PROTECTED_ENVIRONMENTS: frozenset[str] = frozenset({"staging", "prod"})


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="MATTERHUB_", env_file=".env", extra="ignore")

    environment: Environment = "local"
    app_version: str = "0.0.0-dev"
    git_sha: str = "unknown"

    log_level: str = "INFO"
    log_json: bool = True

    # Either a full SQLAlchemy URL, or the individual parts (preferred in Azure so the
    # password can come from Key Vault on its own).
    database_url: SecretStr | None = None
    database_host: str | None = None
    database_port: int = 5432
    database_name: str = "matterhub"
    database_user: str = "matterhub"
    database_password: SecretStr | None = None
    database_sslmode: str = "require"

    auth_mode: Literal["entra", "disabled"] = "entra"
    entra_tenant_id: str | None = None
    entra_audience: str | None = None

    retention_years: int = Field(default=7, ge=1, le=100)

    applicationinsights_connection_string: SecretStr | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "APPLICATIONINSIGHTS_CONNECTION_STRING",
            "MATTERHUB_APPLICATIONINSIGHTS_CONNECTION_STRING",
        ),
    )

    @model_validator(mode="after")
    def _enforce_secure_configuration(self) -> Settings:
        if self.auth_mode == "disabled" and self.environment in PROTECTED_ENVIRONMENTS:
            raise ValueError(f"auth_mode=disabled is not permitted in {self.environment}")
        if self.auth_mode == "entra" and not (self.entra_tenant_id and self.entra_audience):
            raise ValueError("entra_tenant_id and entra_audience are required when auth_mode=entra")
        if (
            self.environment in DEPLOYED_ENVIRONMENTS
            and self.database_url is None
            and self.database_host is None
        ):
            raise ValueError(
                f"a PostgreSQL database must be configured in {self.environment} "
                "(set MATTERHUB_DATABASE_HOST or MATTERHUB_DATABASE_URL)"
            )
        return self

    def sqlalchemy_url(self) -> URL:
        """Resolve the database URL. Falls back to a local SQLite file for local dev."""
        if self.database_url is not None:
            return make_url(self.database_url.get_secret_value())
        if self.database_host is None:
            return make_url("sqlite:///./matterhub.db")
        return URL.create(
            drivername="postgresql+psycopg",
            username=self.database_user,
            password=self.database_password.get_secret_value() if self.database_password else None,
            host=self.database_host,
            port=self.database_port,
            database=self.database_name,
            query={"sslmode": self.database_sslmode},
        )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    # In AKS, the Key Vault CSI driver mounts each secret as a file in this directory,
    # named after the setting (e.g. matterhub_database_password). Secrets therefore never
    # become Kubernetes Secret objects in etcd.
    secrets_dir = os.environ.get("MATTERHUB_SECRETS_DIR")
    return Settings(_secrets_dir=secrets_dir)
