"""Metrics, access logging, correlation IDs and security headers.

Metrics follow the RED method (Rate, Errors, Duration). Labels use the route
*template* (``/api/v1/matters/{matter_id}``), never the raw path, so a scan of random
URLs cannot explode Prometheus label cardinality.
"""

from __future__ import annotations

import logging
import re
import time
import uuid
from collections.abc import Awaitable, Callable

from fastapi import FastAPI, Request, Response
from prometheus_client import Counter, Histogram

from matterhub.config import Settings
from matterhub.logging_config import request_id_ctx

logger = logging.getLogger("matterhub.access")

HTTP_REQUESTS = Counter(
    "http_requests_total",
    "HTTP requests handled",
    ["method", "route", "status"],
)
HTTP_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)
MATTERS_CREATED = Counter(
    "matterhub_matters_created_total",
    "Matters created",
    ["practice_area"],
)
MATTERS_CLOSED = Counter("matterhub_matters_closed_total", "Matters closed")

_QUIET_ROUTES = frozenset({"/healthz", "/readyz", "/metrics"})
_VALID_REQUEST_ID = re.compile(r"^[A-Za-z0-9._-]{1,64}$")

SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
    "Cache-Control": "no-store",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
}


def _request_id(request: Request) -> str:
    supplied = request.headers.get("x-request-id", "")
    # Only trust well-formed IDs from upstream; otherwise mint our own (log injection guard).
    return supplied if _VALID_REQUEST_ID.match(supplied) else uuid.uuid4().hex


def install_observability(app: FastAPI) -> None:
    @app.middleware("http")
    async def observe(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        rid = _request_id(request)
        token = request_id_ctx.set(rid)
        start = time.perf_counter()
        status_code = 500
        try:
            response = await call_next(request)
            status_code = response.status_code
        except Exception:
            logger.exception("unhandled_exception", extra={"path": request.url.path})
            raise
        finally:
            duration = time.perf_counter() - start
            route = request.scope.get("route")
            route_path = getattr(route, "path", "unmatched")
            HTTP_REQUESTS.labels(request.method, route_path, str(status_code)).inc()
            HTTP_LATENCY.labels(request.method, route_path).observe(duration)
            principal = getattr(request.state, "principal", None)
            log = logger.debug if route_path in _QUIET_ROUTES else logger.info
            log(
                "request",
                extra={
                    "method": request.method,
                    "route": route_path,
                    "status": status_code,
                    "duration_ms": round(duration * 1000, 2),
                    "principal": getattr(principal, "subject", None),
                },
            )
            request_id_ctx.reset(token)

        response.headers["X-Request-ID"] = rid
        for header, value in SECURITY_HEADERS.items():
            response.headers.setdefault(header, value)
        return response


def configure_tracing(settings: Settings) -> None:
    """Send traces, metrics and logs to Application Insights when configured.

    Must run before the FastAPI app object is created so auto-instrumentation can
    patch it. Optional: the package is only installed in the container image.
    """
    if settings.applicationinsights_connection_string is None:
        return
    try:
        from azure.monitor.opentelemetry import configure_azure_monitor
    except ImportError:  # pragma: no cover - depends on optional extra
        logger.warning("azure-monitor-opentelemetry not installed; tracing disabled")
        return
    configure_azure_monitor(  # pragma: no cover - needs a real App Insights resource
        connection_string=settings.applicationinsights_connection_string.get_secret_value(),
        logger_name="matterhub",
    )
