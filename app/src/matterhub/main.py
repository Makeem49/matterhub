"""FastAPI application factory."""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from matterhub.auth import TokenValidator
from matterhub.config import Settings, get_settings
from matterhub.db import build_engine, build_session_factory
from matterhub.logging_config import configure_logging
from matterhub.observability import configure_tracing, install_observability
from matterhub.routers import health, matters

logger = logging.getLogger(__name__)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level, settings.log_json)
    configure_tracing(settings)

    engine = build_engine(settings)

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        logger.info(
            "startup",
            extra={
                "environment": settings.environment,
                "version": settings.app_version,
                "git_sha": settings.git_sha,
                "auth_mode": settings.auth_mode,
                "database_backend": engine.url.get_backend_name(),
            },
        )
        yield
        engine.dispose()
        logger.info("shutdown")

    expose_docs = settings.environment != "prod"
    app = FastAPI(
        title="MatterHub API",
        version=settings.app_version,
        description="Track legal matters, their lifecycle and an immutable audit trail.",
        lifespan=lifespan,
        docs_url="/docs" if expose_docs else None,
        redoc_url=None,
        openapi_url="/openapi.json" if expose_docs else None,
    )
    app.state.settings = settings
    app.state.engine = engine
    app.state.session_factory = build_session_factory(engine)
    app.state.token_validator = (
        TokenValidator(settings.entra_tenant_id, settings.entra_audience)
        if settings.auth_mode == "entra"
        and settings.entra_tenant_id is not None
        and settings.entra_audience is not None
        else None
    )

    install_observability(app)
    app.include_router(health.router)
    app.include_router(matters.router)
    return app
