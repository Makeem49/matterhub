"""Operational endpoints: liveness, readiness, version and Prometheus metrics.

* ``/healthz`` (liveness) never touches dependencies. If the database is down, restarting
  every pod would not fix it and would turn a partial outage into a full one.
* ``/readyz`` (readiness) checks the database, so Kubernetes stops routing traffic to a
  pod that cannot serve it.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Request, Response, status
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from matterhub.db import SessionDep
from matterhub.schemas import VersionInfo

logger = logging.getLogger(__name__)
router = APIRouter(tags=["operations"])


@router.get("/healthz", include_in_schema=False)
def liveness() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/readyz", include_in_schema=False)
def readiness(session: SessionDep) -> JSONResponse:
    try:
        session.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        logger.error("readiness_check_failed", extra={"error": type(exc).__name__})
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "unavailable", "checks": {"database": "failing"}},
        )
    return JSONResponse(content={"status": "ready", "checks": {"database": "ok"}})


@router.get("/version", response_model=VersionInfo)
def version(request: Request) -> VersionInfo:
    """Used by the pipeline smoke test to prove the expected build is live."""
    settings = request.app.state.settings
    return VersionInfo(
        version=settings.app_version,
        git_sha=settings.git_sha,
        environment=settings.environment,
    )


@router.get("/metrics", include_in_schema=False)
def metrics() -> Response:
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
