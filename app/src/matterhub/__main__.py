"""Command-line entrypoint. One container image, three roles:

matterhub serve       # the API (Deployment)
matterhub migrate     # apply database migrations (Helm pre-upgrade hook Job)
matterhub retention   # retention review (CronJob)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _serve(host: str, port: int) -> int:
    import uvicorn

    uvicorn.run(
        "matterhub.main:create_app",
        factory=True,
        host=host,
        port=port,
        log_config=None,  # our JSON logging is configured in create_app
        access_log=False,  # the observability middleware writes the access log
        proxy_headers=True,
        forwarded_allow_ips="*",  # only the ingress can reach the pod (NetworkPolicy)
        timeout_graceful_shutdown=20,
        server_header=False,
    )
    return 0


def _migrate() -> int:
    from alembic import command
    from alembic.config import Config

    from matterhub.config import get_settings
    from matterhub.logging_config import configure_logging

    settings = get_settings()
    configure_logging(settings.log_level, settings.log_json)
    cfg = Config()
    cfg.set_main_option("script_location", str(Path(__file__).parent / "migrations"))
    command.upgrade(cfg, "head")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="matterhub", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    serve = sub.add_parser("serve", help="run the HTTP API")
    serve.add_argument("--host", default="0.0.0.0")  # noqa: S104 - container listens on all interfaces
    serve.add_argument("--port", type=int, default=8000)

    sub.add_parser("migrate", help="apply database migrations")

    retention = sub.add_parser("retention", help="flag matters past their retention date")
    retention.add_argument("--dry-run", action="store_true")

    args = parser.parse_args(argv)
    if args.command == "serve":
        return _serve(args.host, args.port)
    if args.command == "migrate":
        return _migrate()

    from matterhub.jobs.retention import main as retention_main

    return retention_main(dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
