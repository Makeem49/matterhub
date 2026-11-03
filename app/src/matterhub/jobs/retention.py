"""Retention review job (runs as a Kubernetes CronJob).

Flags closed matters whose retention date has passed so records managers can review
them. It never deletes data. The job is idempotent (already-flagged matters are
skipped), so a retry after a failure is always safe.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, date, datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from matterhub.config import get_settings
from matterhub.db import build_engine, build_session_factory
from matterhub.logging_config import configure_logging
from matterhub.models import AuditEvent, Matter, MatterStatus

logger = logging.getLogger(__name__)
SYSTEM_ACTOR = "system:retention-job"


@dataclass(frozen=True)
class RetentionResult:
    flagged: int
    dry_run: bool


def run_retention(session: Session, today: date, dry_run: bool = False) -> RetentionResult:
    due = session.scalars(
        select(Matter).where(
            Matter.status == MatterStatus.CLOSED,
            Matter.retention_until <= today,
            Matter.retention_flagged_at.is_(None),
        )
    ).all()

    if not dry_run:
        now = datetime.now(UTC)
        for matter in due:
            matter.retention_flagged_at = now
            session.add(
                AuditEvent(
                    matter_id=matter.id,
                    action="retention_flagged",
                    actor=SYSTEM_ACTOR,
                    details={
                        "retention_until": matter.retention_until.isoformat()
                        if matter.retention_until
                        else None
                    },
                )
            )
        session.commit()

    for matter in due:
        logger.info(
            "retention_due",
            extra={"matter_id": str(matter.id), "ref": matter.reference, "dry_run": dry_run},
        )
    return RetentionResult(flagged=len(due), dry_run=dry_run)


def main(dry_run: bool = False) -> int:
    settings = get_settings()
    configure_logging(settings.log_level, settings.log_json)
    engine = build_engine(settings)
    try:
        with build_session_factory(engine)() as session:
            result = run_retention(session, datetime.now(UTC).date(), dry_run=dry_run)
        logger.info("retention_job_complete", extra={"flagged": result.flagged, "dry_run": dry_run})
        return 0
    except Exception:
        # A non-zero exit marks the Kubernetes Job as failed, which fires the
        # KubeJobFailed alert (see observability/prometheus/alerts.yml).
        logger.exception("retention_job_failed")
        return 1
    finally:
        engine.dispose()
