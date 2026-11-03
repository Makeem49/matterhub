"""Matter (legal case) endpoints."""

from __future__ import annotations

import logging
import uuid
from datetime import UTC, date, datetime
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Request, Response, status
from sqlalchemy import func, select

from matterhub.auth import CanRead, CanWrite
from matterhub.db import SessionDep
from matterhub.models import AuditEvent, Matter, MatterStatus, PracticeArea
from matterhub.observability import MATTERS_CLOSED, MATTERS_CREATED
from matterhub.schemas import AuditEventRead, MatterCreate, MatterPage, MatterRead, MatterUpdate

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1/matters", tags=["matters"])


def add_years(start: date, years: int) -> date:
    try:
        return start.replace(year=start.year + years)
    except ValueError:  # 29 February -> 28 February
        return start.replace(year=start.year + years, day=28)


def new_reference(now: datetime) -> str:
    return f"MAT-{now:%Y}-{uuid.uuid4().hex[:8].upper()}"


def _get_or_404(session: SessionDep, matter_id: uuid.UUID) -> Matter:
    matter = session.get(Matter, matter_id)
    if matter is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Matter not found")
    return matter


@router.get("", response_model=MatterPage)
def list_matters(
    session: SessionDep,
    _: CanRead,
    status_filter: Annotated[MatterStatus | None, Query(alias="status")] = None,
    practice_area: PracticeArea | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> MatterPage:
    stmt = select(Matter)
    if status_filter is not None:
        stmt = stmt.where(Matter.status == status_filter)
    if practice_area is not None:
        stmt = stmt.where(Matter.practice_area == practice_area)
    total = session.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = session.scalars(
        stmt.order_by(Matter.opened_at.desc(), Matter.id).limit(limit).offset(offset)
    ).all()
    return MatterPage(
        items=[MatterRead.model_validate(m) for m in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.post("", response_model=MatterRead, status_code=status.HTTP_201_CREATED)
def create_matter(
    payload: MatterCreate,
    session: SessionDep,
    principal: CanWrite,
    request: Request,
    response: Response,
) -> Matter:
    now = datetime.now(UTC)
    matter = Matter(
        **payload.model_dump(),
        reference=new_reference(now),
        status=MatterStatus.OPEN,
        opened_at=now,
        created_by=principal.name,
    )
    session.add(matter)
    session.flush()
    session.add(
        AuditEvent(
            matter_id=matter.id,
            action="created",
            actor=principal.name,
            details={"reference": matter.reference},
        )
    )
    session.commit()
    MATTERS_CREATED.labels(matter.practice_area.value).inc()
    logger.info("matter_created", extra={"matter_id": str(matter.id), "ref": matter.reference})
    response.headers["Location"] = str(request.url_for("get_matter", matter_id=matter.id))
    return matter


@router.get("/{matter_id}", response_model=MatterRead, name="get_matter")
def get_matter(matter_id: uuid.UUID, session: SessionDep, _: CanRead) -> Matter:
    return _get_or_404(session, matter_id)


@router.patch("/{matter_id}", response_model=MatterRead)
def update_matter(
    matter_id: uuid.UUID,
    payload: MatterUpdate,
    session: SessionDep,
    principal: CanWrite,
    request: Request,
) -> Matter:
    matter = _get_or_404(session, matter_id)
    updates = payload.model_dump(exclude_unset=True)
    if not updates:
        raise HTTPException(status_code=422, detail="No fields to update")

    retention_years: int = request.app.state.settings.retention_years
    changes: dict[str, list[str | None]] = {}
    for field, new_value in updates.items():
        old_value = getattr(matter, field)
        if old_value != new_value:
            changes[field] = [_as_text(old_value), _as_text(new_value)]
            setattr(matter, field, new_value)

    if "status" in changes:
        if matter.status == MatterStatus.CLOSED:
            matter.closed_at = datetime.now(UTC)
            matter.retention_until = add_years(matter.closed_at.date(), retention_years)
            MATTERS_CLOSED.inc()
        else:  # re-opened or put on hold: retention clock no longer applies
            matter.closed_at = None
            matter.retention_until = None
            matter.retention_flagged_at = None

    if changes:
        session.add(
            AuditEvent(
                matter_id=matter.id,
                action="updated",
                actor=principal.name,
                details={"changes": changes},
            )
        )
        session.commit()
        logger.info("matter_updated", extra={"matter_id": str(matter.id), "fields": list(changes)})
    return matter


@router.get("/{matter_id}/audit", response_model=list[AuditEventRead])
def get_audit_trail(matter_id: uuid.UUID, session: SessionDep, _: CanRead) -> list[AuditEvent]:
    _get_or_404(session, matter_id)
    return list(
        session.scalars(
            select(AuditEvent)
            .where(AuditEvent.matter_id == matter_id)
            .order_by(AuditEvent.occurred_at, AuditEvent.id)
        ).all()
    )


def _as_text(value: object) -> str | None:
    if value is None:
        return None
    return str(getattr(value, "value", value))
